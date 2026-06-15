import AVFoundation
import Foundation
import QuartzCore

/// Hör- und Metronom-Engine für Timing-Übungen.
/// - Nimmt den (USB-)Audio-Eingang ab und erkennt Anschläge (Onsets) über die
///   Hüllkurve eines tiefpassgefilterten Signals (Bass-Grundtöne bleiben, der
///   hohe Metronom-Tick wird gedämpft).
/// - Spielt Metronom-Ticks **sample-genau** zu vorgegebenen Zeitpunkten, damit
///   hörbarer Tick und bewerteter Beat exakt zusammenfallen.
///
/// Bewusst kein @MainActor: Der Tap läuft auf dem Audio-Thread und mutiert nur
/// engine-interne Zustände. Callbacks werden vom Aufrufer auf den Main-Thread gehoben.
final class ListeningEngine {
    // Konfiguration (Werte beziehen sich auf das um inputGain verstärkte Signal).
    var onsetThreshold: Float = 0.06
    var refractoryMs: Double = 100
    var lowpassHz: Double = 180
    var inputGain: Float = 25

    /// (Zeit in CACurrentMediaTime-Sekunden, Pegel) eines erkannten Anschlags.
    var onOnset: ((Double, Float) -> Void)?
    /// Auto-skalierter Pegel 0…1 für ein VU-Meter.
    var onLevel: ((Float) -> Void)?

    private(set) var isRunning = false
    private(set) var inputName = "—"

    private let engine = AVAudioEngine()
    private let tickPlayer = AVAudioPlayerNode()
    private var tickAccent: AVAudioPCMBuffer?
    private var tickNormal: AVAudioPCMBuffer?

    // Onset-/Filter-Zustand (nur Audio-Thread).
    private var lp1: Float = 0
    private var lp2: Float = 0
    private var lpCoef: Float = 0.05
    private var prevEnv: Float = 0
    private var lastOnset: Double = 0
    private var noiseFloor: Float = 0.005
    private var levelMax: Float = 0.01
    private var sampleRate: Double = 48000
    private var routeObserver: NSObjectProtocol?

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
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        tickPlayer.stop()
        engine.stop()
        isRunning = false
        // Session zurück auf reine Wiedergabe, damit der Spielton normal bleibt.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Metronom

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
            // Eingang USB-Interface, Ausgang erzwungen auf den iPad-Lautsprecher.
            try? session.overrideOutputAudioPort(.speaker)
            inputName = session.currentRoute.inputs.first?.portName ?? "—"

            let input = engine.inputNode
            let inFormat = input.inputFormat(forBus: 0)
            sampleRate = inFormat.sampleRate

            // Einpoliger Tiefpass-Koeffizient (zweifach kaskadiert ≈ 12 dB/Okt).
            let dt = 1.0 / sampleRate
            let rc = 1.0 / (2.0 * Double.pi * lowpassHz)
            lpCoef = Float(dt / (rc + dt))

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
            forceSpeakerOutput()
        } catch {
            isRunning = false
        }
    }

    /// Eingang USB, Ausgang iPad-Lautsprecher. Der Speaker-Override zieht den
    /// Eingang sonst aufs iPad-Mikro — daher danach den USB-Eingang erneut pinnen.
    /// Idempotent (kein Hin-und-Her, sobald beide Routen passen).
    private func applyRoutePreference() {
        let session = AVAudioSession.sharedInstance()
        let speakerOut = session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
        let usbIn = session.currentRoute.inputs.contains { $0.portType == .usbAudio }
        if speakerOut && usbIn { return }
        try? session.overrideOutputAudioPort(.speaker)
        selectExternalInput(on: session)
    }

    private func forceSpeakerOutput() {
        applyRoutePreference()
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.applyRoutePreference() }
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

    // MARK: - Onset-Erkennung (Audio-Thread)

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        let data = ch[0]

        // Pufferanfang in CACurrentMediaTime-Domäne (Callback ≈ Pufferende).
        let bufStart = CACurrentMediaTime() - Double(n) / sampleRate
        let hop = 256
        var maxEnv: Float = 0
        var i = 0
        while i < n {
            let end = min(i + hop, n)
            var sum: Float = 0
            var c = i
            while c < end {
                let x = data[c] * inputGain
                lp1 += lpCoef * (x - lp1)
                lp2 += lpCoef * (lp1 - lp2)
                sum += lp2 * lp2
                c += 1
            }
            let env = (sum / Float(end - i)).squareRoot()
            if env > maxEnv { maxEnv = env }

            if env < noiseFloor * 1.5 {
                noiseFloor = noiseFloor * 0.995 + env * 0.005
            }
            let dynTh = max(onsetThreshold, noiseFloor * 5)
            let tHop = bufStart + Double(i) / sampleRate
            if env > dynTh && prevEnv <= dynTh && (tHop - lastOnset) * 1000 > refractoryMs {
                lastOnset = tHop
                onOnset?(tHop, env)
            }
            prevEnv = env
            i = end
        }

        if maxEnv > levelMax { levelMax = maxEnv } else { levelMax = max(0.01, levelMax * 0.999) }
        onLevel?(min(1, maxEnv / levelMax))
    }

    private func selectExternalInput(on session: AVAudioSession) {
        guard let inputs = session.availableInputs else { return }
        let preferred = inputs.first { $0.portType == .usbAudio }
            ?? inputs.first { $0.portType != .builtInMic }
        if let preferred { try? session.setPreferredInput(preferred) }
    }
}
