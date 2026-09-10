import AVFoundation
import Foundation

/// Nimmt den (USB-DI-)Audio-Eingang mono mit, während das Play-along läuft.
/// Liefert nach dem Stopp die Rohsamples + Sample-Rate; das Zerschneiden in
/// Teile übernimmt der Aufrufer anhand der Timeline-Zeiten.
final class PartRecorder {
    var onLevel: ((Float) -> Void)?
    private(set) var isRunning = false
    private(set) var inputName = "—"

    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var sampleRate: Double = 48000
    private var levelMax: Float = 0.01
    private let maxSeconds = 480.0   // Speicherlimit (8 min)

    func start(_ completion: @escaping (Bool) -> Void) {
        requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else { completion(false); return }
            self.begin()
            completion(self.isRunning)
        }
    }

    /// Beendet die Aufnahme und liefert die Rohspur.
    func stop() -> (samples: [Float], sampleRate: Double) {
        guard isRunning else { return (samples, sampleRate) }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        return (samples, sampleRate)
    }

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
            // playAndRecord + defaultToSpeaker: Play-along bleibt hörbar, DI wird erfasst.
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true)
            selectExternalInput(on: session)
            inputName = session.currentRoute.inputs.first?.portName ?? "—"

            let input = engine.inputNode
            let format = input.inputFormat(forBus: 0)
            sampleRate = format.sampleRate
            samples.removeAll(keepingCapacity: true)
            let cap = Int(sampleRate * maxSeconds)

            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard let self, let ch = buffer.floatChannelData else { return }
                let n = Int(buffer.frameLength)
                var maxV: Float = 0
                var chunk = [Float](repeating: 0, count: n)
                let data = ch[0]
                for i in 0..<n { let v = data[i]; chunk[i] = v; let a = abs(v); if a > maxV { maxV = a } }
                DispatchQueue.main.async {
                    if self.samples.count < cap { self.samples.append(contentsOf: chunk) }
                    if maxV > self.levelMax { self.levelMax = maxV } else { self.levelMax = max(0.01, self.levelMax * 0.999) }
                    self.onLevel?(min(1, maxV / self.levelMax))
                }
            }
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    private func selectExternalInput(on session: AVAudioSession) {
        guard let inputs = session.availableInputs else { return }
        let preferred = inputs.first { $0.portType == .usbAudio }
            ?? inputs.first { $0.portType != .builtInMic }
        if let preferred { try? session.setPreferredInput(preferred) }
    }
}

/// Mono-WAV (16-bit PCM) aus Float-Samples – für den Upload einzelner Teile.
enum WAVEncoder {
    static func encode(_ samples: [Float], sampleRate: Double) -> Data {
        let numChannels: UInt16 = 1
        let bits: UInt16 = 16
        let sr = UInt32(sampleRate)
        let byteRate = sr * UInt32(numChannels) * UInt32(bits / 8)
        let blockAlign = numChannels * (bits / 8)
        let dataSize = UInt32(samples.count) * UInt32(blockAlign)

        var d = Data(capacity: 44 + Int(dataSize))
        d.append(contentsOf: Array("RIFF".utf8))
        withUnsafeBytes(of: (36 + dataSize).littleEndian) { d.append(contentsOf: $0) }
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        withUnsafeBytes(of: UInt32(16).littleEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1).littleEndian) { d.append(contentsOf: $0) }   // PCM
        withUnsafeBytes(of: numChannels.littleEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: sr.littleEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate.littleEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign.littleEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: bits.littleEndian) { d.append(contentsOf: $0) }
        d.append(contentsOf: Array("data".utf8))
        withUnsafeBytes(of: dataSize.littleEndian) { d.append(contentsOf: $0) }
        for s in samples {
            let clamped = max(-1, min(1, s))
            let i = Int16(clamped * 32767)
            withUnsafeBytes(of: i.littleEndian) { d.append(contentsOf: $0) }
        }
        return d
    }
}
