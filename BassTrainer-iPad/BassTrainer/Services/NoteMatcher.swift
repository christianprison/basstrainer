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

/// Merkt sich pro Position die bestätigten Fingerprints des eigenen Basses,
/// damit die Erkennung sich über die Zeit an das Instrument anpasst.
final class RecognitionMemory {
    private var store: [String: [[Float]]] = [:]
    private let defaultsKey = "noteRecog.memory.v1"
    private let cap = 8

    init() { load() }

    func add(_ fp: [Float], key: String) {
        guard !fp.isEmpty else { return }
        var arr = store[key] ?? []
        arr.append(fp)
        if arr.count > cap { arr.removeFirst(arr.count - cap) }
        store[key] = arr
        save()
    }

    /// Beste Ähnlichkeit zu den gespeicherten Beispielen (–1 = keine).
    func bestSim(_ fp: [Float], key: String) -> Float {
        guard let arr = store[key], !arr.isEmpty else { return -1 }
        return arr.map { NoteMatcher.cosine(fp, $0) }.max() ?? -1
    }

    private func load() {
        if let d = UserDefaults.standard.data(forKey: defaultsKey),
           let s = try? JSONDecoder().decode([String: [[Float]]].self, from: d) { store = s }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(store) { UserDefaults.standard.set(d, forKey: defaultsKey) }
    }
}

/// Vergleicht einen gespielten Ton mit den gespeicherten Bass-Samples und
/// rankt die passenden Saiten/Bünde. Fingerprint = normierte Obertö­n-Magnituden
/// (f0…8·f0, Goertzel); Tonhöhe der Samples wird gemessen (oktavrobust).
@MainActor
final class NoteMatcher {
    let memory = RecognitionMemory()

    private let audio: AudioEngine
    private var cache: [String: [Float]] = [:]          // Sample-Fingerprint je Key
    private var lastInputFP: [Float] = []
    private let harmonics = 8

    /// Reale offene Saiten eines 5-Saiters (klingend): B0/E1/A1/D2/G2.
    private let openRealHz: [Int: Double] = [1: 30.87, 2: 41.20, 3: 55.00, 4: 73.42, 5: 98.00]

    init(audio: AudioEngine) { self.audio = audio }

    private struct Pos {
        let string: Int; let fret: Int; let midi: Int
        let freq: Double; let key: String; let noteName: String
    }

    /// Alle Positionen (5 Saiten × Bund 0…12) mit ihrer DETERMINISTISCHEN realen
    /// Tonhöhe (aus Saite+Bund) – kein DSP-Messen, daher keine Oktavfehler.
    private lazy var allPositions: [Pos] = {
        let map: [(Int, BassString)] = [(1, .b), (2, .e), (3, .a), (4, .d), (5, .g)]
        var res: [Pos] = []
        for (sid, bs) in map {
            guard let open = openRealHz[sid] else { continue }
            for f in 0...12 {
                let freq = open * pow(2.0, Double(f) / 12.0)
                let midi = Int((69.0 + 12.0 * log2(freq / 440.0)).rounded())
                res.append(Pos(string: sid, fret: f, midi: midi, freq: freq,
                               key: FretPosition(string: bs, fret: f).audioKey,
                               noteName: BassIntro.noteName(forMidi: midi)))
            }
        }
        return res
    }()

    /// Bestätigte Auswahl lernen (Fingerprint des letzten Tons → Position).
    func confirm(key: String) { memory.add(lastInputFP, key: key) }

    func rank(input: [Float], sampleRate: Double, f0: Double, maxCandidates: Int = 8)
        async -> (candidates: [ScoredCandidate], bestScore: Double) {
        guard f0 > 20, input.count > 256 else { return ([], 0) }
        let inFP = Self.fingerprint(input, sampleRate: sampleRate, f0: f0, harmonics: harmonics)
        lastInputFP = inFP

        // Kandidaten = ALLE Positionen mit der gleichen realen Tonhöhe wie der
        // gespielte Ton (deterministisch aus Saite/Bund) → alle Lagen, richtige
        // Oktave, unabhängig davon ob ein Sample geladen werden konnte.
        let cands = allPositions.filter { abs(1200 * log2(f0 / $0.freq)) < 50 }
        var scored: [ScoredCandidate] = []
        for c in cands {
            // Klangvergleich nur für die Reihenfolge; fehlt das Sample → neutral.
            let sfp = await sampleFingerprint(c)
            let timbre = sfp != nil ? Double(Self.cosine(inFP, sfp!)) : 0.5
            let userSim = Double(memory.bestSim(inFP, key: c.key))
            let sim = userSim >= 0 ? 0.5 * timbre + 0.5 * userSim : timbre
            scored.append(ScoredCandidate(string: c.string, fret: c.fret, midi: c.midi,
                                          key: c.key, noteName: c.noteName,
                                          probability: 0, score: max(0.001, sim)))
        }
        scored.sort { $0.score > $1.score }
        var top = Array(scored.prefix(maxCandidates))
        let best = top.first?.score ?? 0
        let temp = 0.12
        let exps = top.map { exp($0.score / temp) }
        let sum = exps.reduce(0, +)
        for i in top.indices { top[i].probability = sum > 0 ? exps[i] / sum : 0 }
        return (top, best)
    }

    /// Sample-Fingerprint bei der bekannten realen Tonhöhe der Position (gecacht).
    private func sampleFingerprint(_ c: Pos) async -> [Float]? {
        if let cached = cache[c.key] { return cached }
        guard let url = await audio.ensureSample(key: c.key),
              let pcm = Self.loadPCM(url: url) else { return nil }
        let sr = pcm.sampleRate
        let start = min(max(0, pcm.samples.count - 1), Int(sr * 0.12))
        let end = min(pcm.samples.count, start + Int(sr * 0.30))
        guard end > start + 256 else { return nil }
        let win = Array(pcm.samples[start..<end])
        let fp = Self.fingerprint(win, sampleRate: sr, f0: c.freq, harmonics: harmonics)
        cache[c.key] = fp
        return fp
    }

    // MARK: - DSP

    /// Oktav-Korrektur: ist die Subokta­ve ähnlich stark, liegt die echte
    /// Grundfrequenz tiefer (behebt Oktav-zu-hoch-Fehler der Pitch-Erkennung).
    nonisolated static func refineF0(_ x: [Float], sampleRate: Double, f0: Double) -> Double {
        var f = f0
        for _ in 0..<2 {
            let half = f / 2
            if half < 28 { break }
            let mF = goertzel(x, sampleRate: sampleRate, freq: f)
            let mH = goertzel(x, sampleRate: sampleRate, freq: half)
            if mH > mF * 0.8 { f = half } else { break }
        }
        return f
    }

    /// Sample-Grundfrequenz robust bestimmen (nur um den Hinweis herum, damit
    /// keine Oktavfehler entstehen).
    nonisolated static func measureF0(_ x: [Float], sampleRate: Double, hint: Double) -> Double {
        let cands = [hint / 2, hint, hint * 2].filter { $0 > 25 && $0 < sampleRate / 2 }
        guard !cands.isEmpty else { return hint }
        let mags = cands.map { goertzel(x, sampleRate: sampleRate, freq: $0) }
        guard let maxm = mags.max(), maxm > 0 else { return hint }
        for (i, f) in cands.enumerated() where mags[i] > maxm * 0.7 { return f }  // tiefste starke
        return hint
    }

    nonisolated static func fingerprint(_ x: [Float], sampleRate: Double, f0: Double, harmonics: Int) -> [Float] {
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

    nonisolated static func goertzel(_ x: [Float], sampleRate: Double, freq: Double) -> Float {
        let w = 2 * Double.pi * freq / sampleRate
        let c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in x { let s0 = Double(v) + c * s1 - s2; s2 = s1; s1 = s0 }
        let real = s1 - s2 * cos(w)
        let imag = s2 * sin(w)
        return Float(sqrt(real * real + imag * imag) / Double(max(1, x.count)))
    }

    nonisolated static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        var dot: Float = 0
        for i in 0..<n { dot += a[i] * b[i] }
        return dot
    }

    nonisolated static func loadPCM(url: URL) -> (samples: [Float], sampleRate: Double)? {
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
