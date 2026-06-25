import AVFoundation
import Foundation
import QuartzCore

/// Nimmt den Audio-Eingang ab, erkennt Anschläge (Onsets) **und** bestimmt zu
/// jedem Anschlag die Tonhöhe (YIN, kurz nach dem Attack im Sustain gemessen).
/// Spielt zusätzlich sample-genaue Metronom-Ticks (Einzähler).
///
/// Kein @MainActor: Tap läuft auf dem Audio-Thread; Callbacks werden vom
/// Aufrufer auf den Main-Thread gehoben.
final class IntroRecorder {
    /// 0…1, höher = empfindlicher (mehr erkannte Anschläge). Live verstellbar.
    var sensitivity: Float = 0.6
    var refractoryMs: Double = 70   // Mindestabstand zwischen Tönen
    var inputGain: Float = 12       // Gain (Eingangsverstärkung)
    var gate: Float = 0.02          // Gate (Rauschsperre, absolute Schwelle)
    var attack: Float = 0.4         // schnelle Hüllkurve (0…1, höher = flinker)
    var release: Float = 0.02       // Sustain-Nachführung (klein = träge)

    /// (Zeit in CACurrentMediaTime-Sekunden, MIDI, Clarity) eines erkannten Tons.
    var onNote: ((Double, Int, Float) -> Void)?
    var onLevel: ((Float) -> Void)?
    /// Telemetrie für die Visualisierung: (Pegel/fastEnv, Schwelle, Anschlag?).
    var onMeter: ((Float, Float, Bool) -> Void)?

    private(set) var isRunning = false
    private(set) var inputName = "—"

    private let engine = AVAudioEngine()
    private let tickPlayer = AVAudioPlayerNode()
    private var tickAccent: AVAudioPCMBuffer?
    private var tickNormal: AVAudioPCMBuffer?

    private var detector = PitchDetector()
    private let detectionQueue = DispatchQueue(label: "de.prisons.basstrainer.intro", qos: .userInitiated)
    private let analysisSize = 4096

    // Onset-Zustand (Audio-Thread): adaptiver Transienten-Detektor.
    private var fastEnv: Float = 0          // schnelle Hüllkurve
    private var slowEnv: Float = 0.001      // laufendes Sustain-Niveau
    private var wasAbove = false            // Hysterese
    private var lastOnset: Double = 0
    private var meterHopCounter = 0
    private var meterOnset = false
    private var levelMax: Float = 0.01
    private var sampleRate: Double = 48000

    // Roh-Ringpuffer (volles Band) für die Pitch-Analyse.
    private var ring: [Float] = []
    private var pending: [(onset: Double, analyzeAt: Double)] = []

    // MARK: - Lifecycle

    func start(_ completion: @escaping (Bool) -> Void) {
        requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else { completion(false); return }
            self.begin()
            completion(self.isRunning)
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        tickPlayer.stop()
        engine.stop()
        isRunning = false
        ring.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Plant einen Tick zur Wall-Clock-Zeit `beatTime` (CACurrentMediaTime-Sekunden).
    func scheduleTick(accent: Bool, at beatTime: Double) {
        guard isRunning, let buf = accent ? tickAccent : tickNormal else { return }
        let when = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: beatTime))
        tickPlayer.scheduleBuffer(buf, at: when, options: [], completionHandler: nil)
    }

    // MARK: - Setup

    private func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: completion(true)
        case .denied: completion(false)
        case .undetermined:
            AVAudioApplication.requestRecordPermission { g in DispatchQueue.main.async { completion(g) } }
        @unknown default: completion(false)
        }
    }

    private func begin() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true)
            selectExternalInput(on: session)
            inputName = session.currentRoute.inputs.first?.portName ?? "—"

            let input = engine.inputNode
            let inFormat = input.inputFormat(forBus: 0)
            sampleRate = inFormat.sampleRate

            engine.attach(tickPlayer)
            let outFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            engine.connect(tickPlayer, to: engine.mainMixerNode, format: outFormat)
            tickAccent = makeTick(freq: 1200, format: outFormat)
            tickNormal = makeTick(freq: 800, format: outFormat)

            input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buf, _ in
                self?.process(buf)
            }

            engine.prepare()
            try engine.start()
            tickPlayer.play()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    private func makeTick(freq: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(sr * 0.05)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let ch = buf.floatChannelData else { return nil }
        buf.frameLength = frames
        let channels = Int(format.channelCount)
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let env = exp(-t * 40.0) * 0.4
            let s = Float(sin(2.0 * Double.pi * freq * t) * env)
            for c in 0..<channels { ch[c][i] = s }
        }
        return buf
    }

    private func selectExternalInput(on session: AVAudioSession) {
        guard let inputs = session.availableInputs else { return }
        let preferred = inputs.first { $0.portType == .usbAudio }
            ?? inputs.first { $0.portType != .builtInMic }
        if let preferred { try? session.setPreferredInput(preferred) }
    }

    // MARK: - Verarbeitung (Audio-Thread)

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        let data = ch[0]

        let bufStart = CACurrentMediaTime() - Double(n) / sampleRate
        let bufEnd = bufStart + Double(n) / sampleRate

        // Rohpuffer füllen (für Pitch).
        for k in 0..<n { ring.append(data[k]) }
        let cap = Int(sampleRate * 0.5)
        if ring.count > cap { ring.removeFirst(ring.count - cap) }

        // Adaptiver Transienten-Detektor (breitbandig): ein Anschlag = relativer
        // Pegel-Anstieg über dem laufenden Sustain — fängt auch wiederholte/hohe Töne.
        let hop = 256
        let ratio = 2.0 - sensitivity * 0.85          // 1.15 (empfindlich) … 2.0
        var maxEnv: Float = 0
        var i = 0
        while i < n {
            let end = min(i + hop, n)
            var sum: Float = 0
            var c = i
            while c < end {
                let x = data[c] * inputGain
                sum += x * x
                c += 1
            }
            let env = (sum / Float(end - i)).squareRoot()
            if env > maxEnv { maxEnv = env }
            fastEnv += attack * (env - fastEnv)
            slowEnv += release * (env - slowEnv)
            let thresh = max(gate, slowEnv * ratio)
            let tHop = bufStart + Double(i) / sampleRate
            var onsetHere = false
            if fastEnv > thresh {
                if !wasAbove && (tHop - lastOnset) * 1000 > refractoryMs {
                    lastOnset = tHop
                    pending.append((onset: tHop, analyzeAt: tHop + 0.09))   // Pitch im Sustain
                    onsetHere = true
                }
                wasAbove = true
            } else if fastEnv < thresh * 0.7 {
                wasAbove = false
            }

            // Telemetrie für die Visualisierung (dezimiert ~30 Hz).
            if onsetHere { meterOnset = true }
            meterHopCounter += 1
            if meterHopCounter >= 6 {
                onMeter?(fastEnv, thresh, meterOnset)
                meterHopCounter = 0
                meterOnset = false
            }
            i = end
        }

        // Fällige Pitch-Analysen ausführen.
        if !pending.isEmpty {
            let snapshot = ring
            var stillPending: [(onset: Double, analyzeAt: Double)] = []
            for p in pending {
                guard p.analyzeAt <= bufEnd else { stillPending.append(p); continue }
                let window = Array(snapshot.suffix(analysisSize))
                let onset = p.onset
                let det = detector
                let sr = sampleRate
                detectionQueue.async { [weak self] in
                    guard window.count >= 1024, let result = det.detect(window, sampleRate: sr) else { return }
                    let midi = BassIntro.midi(forFrequency: result.frequency)
                    self?.onNote?(onset, midi, result.clarity)
                }
            }
            pending = stillPending
        }

        if maxEnv > levelMax { levelMax = maxEnv } else { levelMax = max(0.01, levelMax * 0.999) }
        onLevel?(min(1, maxEnv / levelMax))
    }
}
