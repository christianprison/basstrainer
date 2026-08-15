import AVFoundation
import Foundation

/// Ein bewerteter Kandidat (Saite/Bund) für einen gespielten Ton.
struct ScoredCandidate: Identifiable, Equatable {
    let id = UUID()
    let string: Int      // 1=B … 5=G
    let fret: Int
    let midi: Int
    let key: String      // Sample-Key, z. B. "E_005"
    let noteName: String
    var probability: Double
    var score: Double
}

/// Vergleicht einen gespielten Ton mit den gespeicherten Bass-Samples und
/// rankt die passenden Saiten/Bünde. Kern: ein Obertö­n-Fingerprint (Magnituden
/// bei f0…8·f0 via Goertzel), verglichen per Cosinus-Ähnlichkeit.
@MainActor
final class NoteMatcher {
    private let audio: AudioEngine
    private var fpCache: [String: [Float]] = [:]
    private let harmonics = 8

    init(audio: AudioEngine) { self.audio = audio }

    private struct Pos {
        let string: Int; let fret: Int; let midi: Int
        let freq: Double; let key: String; let noteName: String
    }

    /// Alle Positionen (5 Saiten × Bund 0…12) mit Tonhöhe + Sample-Key.
    private lazy var allPositions: [Pos] = {
        let map: [(Int, BassString)] = [(1, .b), (2, .e), (3, .a), (4, .d), (5, .g)]
        var res: [Pos] = []
        for (sid, bs) in map {
            for f in 0...12 {
                let pos = FretPosition(string: bs, fret: f)
                let freq = pos.frequency
                let midi = Int((69.0 + 12.0 * log2(freq / 440.0)).rounded())
                res.append(Pos(string: sid, fret: f, midi: midi, freq: freq,
                               key: pos.audioKey, noteName: BassIntro.noteName(forMidi: midi)))
            }
        }
        return res
    }()

    /// Rankt die Kandidaten für einen gespielten Ton (Eingangsfenster + f0).
    func rank(input: [Float], sampleRate: Double, f0: Double, maxCandidates: Int = 4)
        async -> (candidates: [ScoredCandidate], bestScore: Double) {
        guard f0 > 20, input.count > 256 else { return ([], 0) }
        let inFP = Self.fingerprint(input, sampleRate: sampleRate, f0: f0, harmonics: harmonics)

        // Kandidaten: Positionen im Umkreis von ~1,5 Halbtönen um die gespielte Tonhöhe.
        let cands = allPositions.filter { abs(1200 * log2(f0 / $0.freq)) < 160 }
        var scored: [ScoredCandidate] = []
        for c in cands {
            guard let fp = await sampleFingerprint(c) else { continue }
            let timbre = Double(Self.cosine(inFP, fp))
            let cents = 1200 * log2(f0 / c.freq)
            let pitchScore = exp(-pow(cents / 70.0, 2))       // Tonhöhen-Nähe
            let score = pitchScore * (0.35 + 0.65 * max(0, timbre))
            scored.append(ScoredCandidate(string: c.string, fret: c.fret, midi: c.midi,
                                          key: c.key, noteName: c.noteName, probability: 0, score: score))
        }
        scored.sort { $0.score > $1.score }
        var top = Array(scored.prefix(maxCandidates))
        let best = top.first?.score ?? 0
        // Softmax → Wahrscheinlichkeiten.
        let temp = 0.15
        let exps = top.map { exp($0.score / temp) }
        let sum = exps.reduce(0, +)
        for i in top.indices { top[i].probability = sum > 0 ? exps[i] / sum : 0 }
        return (top, best)
    }

    private func sampleFingerprint(_ c: Pos) async -> [Float]? {
        if let fp = fpCache[c.key] { return fp }
        guard let url = await audio.ensureSample(key: c.key),
              let pcm = Self.loadPCM(url: url) else { return nil }
        let sr = pcm.sampleRate
        // Stabiles Fenster hinter dem Attack.
        let startIdx = min(max(0, pcm.samples.count - 1), Int(sr * 0.12))
        let endIdx = min(pcm.samples.count, startIdx + Int(sr * 0.25))
        guard endIdx > startIdx else { return nil }
        let window = Array(pcm.samples[startIdx..<endIdx])
        let fp = Self.fingerprint(window, sampleRate: sr, f0: c.freq, harmonics: harmonics)
        fpCache[c.key] = fp
        return fp
    }

    // MARK: - DSP

    static func fingerprint(_ x: [Float], sampleRate: Double, f0: Double, harmonics: Int) -> [Float] {
        var v = [Float](repeating: 0, count: harmonics)
        for k in 1...harmonics {
            let f = f0 * Double(k)
            if f >= sampleRate / 2 { break }
            v[k - 1] = goertzel(x, sampleRate: sampleRate, freq: f)
        }
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        if norm > 0 { for i in v.indices { v[i] /= norm } }
        return v
    }

    static func goertzel(_ x: [Float], sampleRate: Double, freq: Double) -> Float {
        let w = 2 * Double.pi * freq / sampleRate
        let c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in x { let s0 = Double(v) + c * s1 - s2; s2 = s1; s1 = s0 }
        let real = s1 - s2 * cos(w)
        let imag = s2 * sin(w)
        return Float(sqrt(real * real + imag * imag) / Double(max(1, x.count)))
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        var dot: Float = 0
        for i in 0..<n { dot += a[i] * b[i] }
        return dot   // beide L2-normiert → Cosinus
    }

    static func loadPCM(url: URL) -> (samples: [Float], sampleRate: Double)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let fmt = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { return nil }
        do { try file.read(into: buf) } catch { return nil }
        guard let ch = buf.floatChannelData else { return nil }
        let count = Int(buf.frameLength)
        return (Array(UnsafeBufferPointer(start: ch[0], count: count)), fmt.sampleRate)
    }
}
