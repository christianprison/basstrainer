import AVFoundation
import Foundation

/// Audio engine built on AVAudioPlayer for maximum device compatibility.
/// MP3 samples are downloaded and cached to disk; synth sounds are generated
/// as in-memory WAV data. No AVAudioEngine usage — avoids hardware node crashes.
final class AudioEngine: ObservableObject {
    @Published var isLoaded = false
    private var activePlayers: [AVAudioPlayer] = []
    private let cacheDirectory: URL
    private let sampleRate: Double = 44100.0

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

        // Set up audio session immediately — not lazily
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            print("[Audio] Session active")
        } catch {
            print("[Audio] Session setup failed: \(error)")
        }
    }

    // MARK: - Cache helpers

    private func cachedFileURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).mp3")
    }

    private func sampleExists(for key: String) -> Bool {
        FileManager.default.fileExists(atPath: cachedFileURL(for: key).path)
    }

    // MARK: - Preload

    func preload() async {
        let allKeys = Array(audioSources.keys)
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            for key in allKeys {
                if sampleExists(for: key) { continue }
                if inFlight >= 6 {
                    await group.next()
                    inFlight -= 1
                }
                let urlString = audioSources[key]!
                let cachedFile = cachedFileURL(for: key)
                group.addTask {
                    guard let url = URL(string: urlString) else { return }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        try data.write(to: cachedFile)
                        print("[Audio] Downloaded: \(key)")
                    } catch {
                        print("[Audio] Download failed \(key): \(error)")
                    }
                }
                inFlight += 1
            }
        }
        await MainActor.run { isLoaded = true }
        print("[Audio] Preload complete – \(allKeys.count) samples")
    }

    // MARK: - Play Bass Note

    func playBassNote(position: FretPosition) {
        let key = position.audioKey
        let fileURL = cachedFileURL(for: key)

        if sampleExists(for: key) {
            playFile(fileURL)
        } else {
            playSynthBass(frequency: position.frequency)
            let urlString = audioSources[key]
            Task {
                guard let urlStr = urlString, let url = URL(string: urlStr) else { return }
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    try data.write(to: fileURL)
                    print("[Audio] Downloaded on demand: \(key)")
                } catch {
                    print("[Audio] On-demand download failed \(key): \(error)")
                }
            }
        }
    }

    // MARK: - Synthesized Sounds

    func playSynthBass(frequency: Double, duration: Double = 0.8) {
        let frameCount = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 3.0) * 0.4
            let fundamental = sin(2.0 * .pi * frequency * t)
            let harmonic2 = sin(2.0 * .pi * frequency * 2.0 * t) * 0.3
            let harmonic3 = sin(2.0 * .pi * frequency * 3.0 * t) * 0.1
            samples[i] = Float(envelope * (fundamental + harmonic2 + harmonic3))
        }

        playSamples(samples)
    }

    func playFanfare() {
        let notes: [(freq: Double, start: Double)] = [
            (523.25, 0.0), (659.25, 0.15), (783.99, 0.30), (1046.50, 0.45),
        ]
        let totalDuration = 0.75
        let frameCount = Int(sampleRate * totalDuration)
        var samples = [Float](repeating: 0, count: frameCount)

        for note in notes {
            let startFrame = Int(note.start * sampleRate)
            let noteFrames = Int(0.3 * sampleRate)
            for j in 0..<noteFrames {
                let frame = startFrame + j
                guard frame < frameCount else { break }
                let t = Double(j) / sampleRate
                let envelope = exp(-t * 5.0) * 0.3
                samples[frame] += Float(envelope * sin(2.0 * .pi * note.freq * t))
            }
        }

        playSamples(samples)
    }

    func playFireworks() {
        let totalDuration = 1.5
        let frameCount = Int(sampleRate * totalDuration)
        var samples = [Float](repeating: 0, count: frameCount)

        let puffFrames = Int(0.15 * sampleRate)
        for i in 0..<puffFrames {
            let t = Double(i) / sampleRate
            let freq = 80.0 * exp(-t * 10.0)
            let envelope = exp(-t * 20.0) * 0.3
            samples[i] = Float(envelope * sin(2.0 * .pi * freq * t))
        }

        let crackleStart = Int(0.55 * sampleRate)
        for _ in 0..<15 {
            let offset = Int(Double.random(in: 0..<0.8) * sampleRate)
            let burstLength = Int(Double.random(in: 0.02...0.05) * sampleRate)
            for j in 0..<burstLength {
                let frame = crackleStart + offset + j
                guard frame < frameCount else { break }
                let t = Double(j) / Double(burstLength)
                let envelope = (1.0 - t) * Double.random(in: 0.05...0.15)
                samples[frame] += Float(envelope * Double.random(in: -1...1))
            }
        }

        playSamples(samples)
    }

    func playGroove(beatNumber: Int) {
        let duration = 0.15
        let frameCount = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: frameCount)

        let beat = beatNumber % 4

        if beat == 0 || beat == 2 {
            for i in 0..<frameCount {
                let t = Double(i) / sampleRate
                let freq = 150.0 * exp(-t * 20.0)
                let envelope = exp(-t * 15.0) * 0.6
                samples[i] += Float(envelope * sin(2.0 * .pi * freq * t))
            }
        }

        if beat == 1 || beat == 3 {
            for i in 0..<frameCount {
                let t = Double(i) / sampleRate
                let envelope = exp(-t * 20.0) * 0.3
                let tone = sin(2.0 * .pi * 200.0 * t) * 0.5
                let noise = Double.random(in: -1...1)
                samples[i] += Float(envelope * (tone + noise))
            }
        }

        let hihatFrames = min(Int(0.03 * sampleRate), frameCount)
        for i in 0..<hihatFrames {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 100.0) * 0.15
            samples[i] += Float(envelope * Double.random(in: -1...1))
        }

        playSamples(samples)
    }

    // MARK: - Private: WAV Playback

    private func playSamples(_ samples: [Float]) {
        // Build WAV data in memory
        let wavData = buildWav(samples: samples)

        // Clean up finished players
        activePlayers.removeAll { !$0.isPlaying }

        do {
            // fileTypeHint is critical — without it AVAudioPlayer may not recognize in-memory WAV
            let player = try AVAudioPlayer(data: wavData, fileTypeHint: AVFileType.wav.rawValue)
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            activePlayers.append(player)
            print("[Audio] Playing synth sound (\(samples.count) samples, \(activePlayers.count) active)")
        } catch {
            print("[Audio] Synth play FAILED: \(error)")
        }
    }

    private func buildWav(samples: [Float]) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sr = UInt32(sampleRate)
        let byteRate = sr * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count) * UInt32(blockAlign)

        var d = Data(capacity: 44 + Int(dataSize))

        // RIFF header
        d.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        withUnsafeBytes(of: (36 + dataSize).littleEndian) { d.append(contentsOf: $0) }
        d.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        d.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        withUnsafeBytes(of: UInt32(16).littleEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1).littleEndian) { d.append(contentsOf: $0) } // PCM
        withUnsafeBytes(of: numChannels.littleEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: sr.littleEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate.littleEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign.littleEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { d.append(contentsOf: $0) }

        // data chunk
        d.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        withUnsafeBytes(of: dataSize.littleEndian) { d.append(contentsOf: $0) }

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: int16.littleEndian) { d.append(contentsOf: $0) }
        }

        return d
    }

    private func playFile(_ url: URL) {
        activePlayers.removeAll { !$0.isPlaying }
        do {
            let player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.mp3.rawValue)
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            activePlayers.append(player)
            print("[Audio] Playing file: \(url.lastPathComponent) (\(activePlayers.count) active)")
        } catch {
            print("[Audio] File play FAILED: \(error)")
        }
    }
}
