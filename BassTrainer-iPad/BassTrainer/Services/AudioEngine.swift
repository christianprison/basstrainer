import AVFoundation
import Foundation

/// Audio engine that plays bass note samples and synthesized sound effects.
/// Downloads MP3 samples from remote storage on first use and caches them locally.
/// Falls back to synthesized tones if samples are unavailable.
/// Gracefully degrades to silence if audio hardware is unavailable (e.g. Simulator).
final class AudioEngine: ObservableObject {
    private var engine: AVAudioEngine?
    private var audioBuffers: [String: AVAudioPCMBuffer] = [:]
    private var isEngineRunning = false
    private let cacheDirectory: URL
    private let sampleRate: Double = 44100.0
    private lazy var audioFormat: AVAudioFormat? = {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    }()

    // Remote audio sample URLs (same as the web version)
    private let audioSources: [String: String] = [
        "B_000": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_000-HuarDXlqG9k2obnYN6LzuNHMSpWcGV.mp3",
        "B_001": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_001-f3OrO0SgJPFxvx7rX2aA0oMP3AqEeG.mp3",
        "B_002": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_002-FFw2OoJD4N45pcIlMZqrGaC8WtyG1t.mp3",
        "B_003": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_003-9VJALzxc6H1XO4Zhyp9SyUxzfZPvT9.mp3",
        "B_004": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_004-r9hOWguwSpfej0wx4W6PZx922oMV8x.mp3",
        "B_005": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_005-Hyv3goJ1kxqzCB07aSpagt86djm7Sx.mp3",
        "B_006": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_006-2rkSM8c5rRmZBldCoV0DfhQt7Ryi7O.mp3",
        "B_007": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_007-b5XX2PXmiC0YXy673hyx1kRRTpA7gH.mp3",
        "B_008": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_008-stexKSTXXjb9p38ObKUxHfUXsL1g6Z.mp3",
        "B_009": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_009-mGggrgKtv3IsJBzOa91zu8pYz5E3kj.mp3",
        "B_010": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_010-i3Sd8v46HoMQH0An3mKQnYnx7H7x2N.mp3",
        "B_011": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_011-OzWEIbXeh1kG25izknG7OwR32h7Mdz.mp3",
        "B_012": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_012-16q5CRzepLGKywDuVxOGruoMyxMC4L.mp3",
        "E_000": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_000-Mls73aLJi5avZVumN2lSsLBm48Xo6V.mp3",
        "E_001": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_001-Iis0oWs47xxb0C3WPgsMSUnDyX1ifF.mp3",
        "E_002": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_002-zDb9oK04AB0We8E3nZ3XNewR5Hrjy0.mp3",
        "E_003": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_003-PwABivhFb6Jd9Gkn47pU3xwlNFeF3A.mp3",
        "E_004": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_004-3G1UOkMjV6lBJK1177QAeEIgz8y9gR.mp3",
        "E_005": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_005-SOO9YHHxtpBcFwSYZXiqaw8b7Qa3yW.mp3",
        "E_006": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_006-m1BDiHkqRhPPDGp6BQ8Opr6VkUwQaZ.mp3",
        "E_007": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_007-bpgQd1du9ZnQxWnLj3uW2Zb64Jn17x.mp3",
        "E_008": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_008-0yUNO07m5mAqSfox9n1580pVJmPO7q.mp3",
        "E_009": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_009-Mb59LSMVYvpoTnE2pfl2LaZkG1jLpz.mp3",
        "E_010": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_010-2JunBaYNCjEykUyEDPZ1Ha0hRLGWIi.mp3",
        "E_011": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_011-1aHRCBxPzx87nFAmjWO9cnZEuNZCTi.mp3",
        "E_012": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_012-SwVx4AQafeiqUawrAbFQr98qOHcRke.mp3",
        "A_000": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_000-eTewYhiSvyHQoZj0lXev99yRPKWq1a.mp3",
        "A_001": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_001-D13P8MnJYt7g4ohepaZVDkDGAgw072.mp3",
        "A_002": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_002-TBXAQzb1HxNXiOKQ1IE6bxPjR1MOpb.mp3",
        "A_003": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_003-bb2TaCw0kEULJ32JqpJSk42odSEJKE.mp3",
        "A_004": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_004-YEauo2JtpvdUHDgPf8inF483Nlg5Sw.mp3",
        "A_005": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_005-AbVERKGEmHAvgaMqaJTcRngnjK5ZhZ.mp3",
        "A_006": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_006-gBq8qucwvxvfLgxpnRoKiuloZgFNp4.mp3",
        "A_007": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_007-lPsQHGKuWlxvtMfg3mLfb0cOjU8Xlv.mp3",
        "A_008": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_008-x8z6siThbvFEvgCmbE36yHJ8x6qufa.mp3",
        "A_009": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_009-9nWMs3sYMb2lptOuwLfUJoABSRbVF2.mp3",
        "A_010": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_010-c8Dk0wZnoskE4bhVl0UKu9gvsLsPM8.mp3",
        "A_011": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_011-qPN3aITbDcpXFr52WEr2kJEweqq7Ux.mp3",
        "A_012": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_012-ENVY87SBxt7hHyH6gcQM0Q16qdhMja.mp3",
        "D_000": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_000-UwWNAJZcUk6g6a46GeL2SBkO5JcBIr.mp3",
        "D_001": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_001-EYNFs7eKHEtTBuPQqusKEktkWoixwR.mp3",
        "D_002": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_002-d0eIuNLQrkMx9xRi6rbEZD2Lzzwvdb.mp3",
        "D_003": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_003-0qjgaQb08jNhGk2CeM3nWZCIuUjdX1.mp3",
        "D_004": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_004-yRYTil0XOPX7gAcPBw2qWW2iW2IyJk.mp3",
        "D_005": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_005-fS93tDvULpctbUEpVzrbAfkhq9Wv16.mp3",
        "D_006": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_006-tJUuoq6BUsF9mIIVwMvhuvpcQPniXC.mp3",
        "D_007": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_007-3Aq2sN7ktWexhsxlAWaIG0hdr96cvO.mp3",
        "D_008": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_008-U7e7B1drb6THzaIobCHwKtI6NPSmyb.mp3",
        "D_009": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_009-dmVZoKql2pQKJWHqPuv5WahF7JdqHN.mp3",
        "D_010": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_010-wa95JebuWZfiasjcEPzk9sWDDwI67b.mp3",
        "D_011": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_011-VSW9Wl3CAa5eefO7rxes3CezfXa9ZP.mp3",
        "D_012": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_012-1J6IMbD8YA4pXq3norPqdcGF02huEl.mp3",
        "G_000": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_000-1I3BvCZdBjrnSGEObtNAcWbl3Ue9sK.mp3",
        "G_001": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_001-f4OzSoRNLUV4ttZtwkfdEdnX0UiL6S.mp3",
        "G_002": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_002-xVAlpRn8bfAwgUSEZAAkyKzmNJZzlW.mp3",
        "G_003": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_003-rOi4FzM8k6OtM3Srs2kCLnqle9bx3H.mp3",
        "G_004": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_004-xqCIVxe8ydXS7sgpa9l1K7KfoVBrsB.mp3",
        "G_005": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_005-yl58C5IsMj6lGTvXw0EdSGvr16rUDk.mp3",
        "G_006": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_006-AfXZANkuZrVCW69e8j7r7acnltoZex.mp3",
        "G_007": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_007-uk3aMhe4vz02jtcbFvssLHL9xRACoU.mp3",
        "G_008": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_008-GFshil0BoKSx77JN0fiKMVToicicvf.mp3",
        "G_009": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_009-iiCZ5WAqHGdbNzoyAh9OQUwhGWIigR.mp3",
        "G_010": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_010-HBiqpQxxjivJViUBxfSevK3Q9gWFKy.mp3",
        "G_011": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_011-uP0kHy5ntcNqLFRBILlCFPQEIdmw71.mp3",
        "G_012": "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_012-LujHVc3YzUvWkDDvdMi9BeNqsRBMXC.mp3",
    ]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("BassAudioCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        setupAudioSession()
    }

    // MARK: - Setup

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[Audio] Failed to setup audio session: \(error)")
        }
    }

    /// Lazily start the engine on first use. Returns true if ready to play.
    private func ensureEngineRunning() -> Bool {
        if isEngineRunning, engine != nil { return true }

        let newEngine = AVAudioEngine()
        // Attach a dummy mixer to validate the graph before starting.
        // On the Simulator this can throw if no audio hardware is present.
        do {
            // Force the engine to build its graph; this is where the
            // "outputNode != nullptr" assertion fires on the Simulator.
            _ = newEngine.mainMixerNode // triggers implicit output node attach
            try newEngine.start()
            engine = newEngine
            isEngineRunning = true
            print("[Audio] Engine started successfully")
            return true
        } catch {
            print("[Audio] Engine unavailable (Simulator?): \(error)")
            engine = nil
            isEngineRunning = false
            return false
        }
    }

    // MARK: - Preload

    func preload() async {
        let keysToPreload = Array(audioSources.keys.prefix(10))
        await withTaskGroup(of: Void.self) { group in
            for key in keysToPreload {
                group.addTask { [weak self] in
                    await self?.loadAudioBuffer(key: key)
                }
            }
        }
        print("[Audio] Preload complete")
    }

    // MARK: - Play Bass Note

    func playBassNote(position: FretPosition) {
        let key = position.audioKey
        if let buffer = audioBuffers[key] {
            playBuffer(buffer)
        } else {
            playSynthBass(frequency: position.frequency)
            Task {
                await loadAudioBuffer(key: key)
            }
        }
    }

    // MARK: - Synthesized Sounds

    func playSynthBass(frequency: Double, duration: Double = 0.8) {
        guard ensureEngineRunning(), let engine = engine, let format = audioFormat else { return }

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 3.0) * 0.4
            let fundamental = sin(2.0 * .pi * frequency * t)
            let harmonic2 = sin(2.0 * .pi * frequency * 2.0 * t) * 0.3
            let harmonic3 = sin(2.0 * .pi * frequency * 3.0 * t) * 0.1
            data[i] = Float(envelope * (fundamental + harmonic2 + harmonic3))
        }

        playGeneratedBuffer(buffer, format: format, on: engine)
    }

    func playFanfare() {
        guard ensureEngineRunning(), let engine = engine, let format = audioFormat else { return }

        let notes: [(freq: Double, start: Double)] = [
            (523.25, 0.0),
            (659.25, 0.15),
            (783.99, 0.30),
            (1046.50, 0.45),
        ]
        let totalDuration = 0.75
        let frameCount = AVAudioFrameCount(sampleRate * totalDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) { data[i] = 0 }

        for note in notes {
            let startFrame = Int(note.start * sampleRate)
            let noteDuration = 0.3
            let noteFrames = Int(noteDuration * sampleRate)
            for j in 0..<noteFrames {
                let frame = startFrame + j
                guard frame < Int(frameCount) else { break }
                let t = Double(j) / sampleRate
                let envelope = exp(-t * 5.0) * 0.3
                let sample = sin(2.0 * .pi * note.freq * t)
                data[frame] += Float(envelope * sample)
            }
        }

        playGeneratedBuffer(buffer, format: format, on: engine)
    }

    func playFireworks() {
        guard ensureEngineRunning(), let engine = engine, let format = audioFormat else { return }

        let totalDuration = 1.5
        let frameCount = AVAudioFrameCount(sampleRate * totalDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) { data[i] = 0 }

        let puffFrames = Int(0.15 * sampleRate)
        for i in 0..<puffFrames {
            let t = Double(i) / sampleRate
            let freq = 80.0 * exp(-t * 10.0)
            let envelope = exp(-t * 20.0) * 0.3
            data[i] = Float(envelope * sin(2.0 * .pi * freq * t))
        }

        let crackleStart = Int(0.55 * sampleRate)
        for _ in 0..<15 {
            let offset = Int(Double.random(in: 0..<0.8) * sampleRate)
            let burstLength = Int(Double.random(in: 0.02...0.05) * sampleRate)
            for j in 0..<burstLength {
                let frame = crackleStart + offset + j
                guard frame < Int(frameCount) else { break }
                let t = Double(j) / Double(burstLength)
                let envelope = (1.0 - t) * Double.random(in: 0.05...0.15)
                data[frame] += Float(envelope * Double.random(in: -1...1))
            }
        }

        playGeneratedBuffer(buffer, format: format, on: engine)
    }

    func playGroove(beatNumber: Int) {
        guard ensureEngineRunning(), let engine = engine, let format = audioFormat else { return }

        let duration = 0.15
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) { data[i] = 0 }

        let beat = beatNumber % 4

        if beat == 0 || beat == 2 {
            for i in 0..<Int(frameCount) {
                let t = Double(i) / sampleRate
                let freq = 150.0 * exp(-t * 20.0)
                let envelope = exp(-t * 15.0) * 0.6
                data[i] += Float(envelope * sin(2.0 * .pi * freq * t))
            }
        }

        if beat == 1 || beat == 3 {
            for i in 0..<Int(frameCount) {
                let t = Double(i) / sampleRate
                let envelope = exp(-t * 20.0) * 0.3
                let tone = sin(2.0 * .pi * 200.0 * t) * 0.5
                let noise = Double.random(in: -1...1)
                data[i] += Float(envelope * (tone + noise))
            }
        }

        let hihatFrames = min(Int(0.03 * sampleRate), Int(frameCount))
        for i in 0..<hihatFrames {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 100.0) * 0.15
            data[i] += Float(envelope * Double.random(in: -1...1))
        }

        playGeneratedBuffer(buffer, format: format, on: engine)
    }

    // MARK: - Private Helpers

    private func playGeneratedBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat, on engine: AVAudioEngine) {
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        playerNode.scheduleBuffer(buffer) {
            DispatchQueue.main.async {
                engine.detach(playerNode)
            }
        }
        playerNode.play()
    }

    private func loadAudioBuffer(key: String) async {
        guard audioBuffers[key] == nil, let urlString = audioSources[key] else { return }

        let cachedFile = cacheDirectory.appendingPathComponent("\(key).mp3")
        var audioData: Data?

        if FileManager.default.fileExists(atPath: cachedFile.path) {
            audioData = try? Data(contentsOf: cachedFile)
        } else {
            guard let url = URL(string: urlString) else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                audioData = data
                try? data.write(to: cachedFile)
            } catch {
                print("[Audio] Failed to download \(key): \(error)")
                return
            }
        }

        guard let data = audioData else { return }

        do {
            let tempFile = cacheDirectory.appendingPathComponent("\(key)_temp.mp3")
            try data.write(to: tempFile)
            let audioFile = try AVAudioFile(forReading: tempFile)
            let format = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
            try audioFile.read(into: buffer)
            audioBuffers[key] = buffer
            try? FileManager.default.removeItem(at: tempFile)
            print("[Audio] Loaded: \(key)")
        } catch {
            print("[Audio] Failed to decode \(key): \(error)")
        }
    }

    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        guard ensureEngineRunning(), let engine = engine else { return }

        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: buffer.format)
        playerNode.scheduleBuffer(buffer) {
            DispatchQueue.main.async {
                engine.detach(playerNode)
            }
        }
        playerNode.play()
    }
}
