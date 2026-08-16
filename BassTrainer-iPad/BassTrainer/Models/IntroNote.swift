import Foundation

/// Ein Ton eines Song-Anfangs. Gelesen aus `song_intro_public`,
/// geschrieben (Kurator) nach `song_intros`.
struct IntroNote: Identifiable, Codable, Equatable {
    var id = UUID()            // nur clientseitig
    var idx: Int
    var midi: Int              // klingende Tonhöhe
    var beat: Double           // Viertel ab Downbeat (Auftakt negativ)
    var durationBeats: Double?
    var string: Int?           // 1=B … 5=G (klingende Konvention, 5-Saiter)
    var fret: Int?
    var noteName: String?

    enum CodingKeys: String, CodingKey {
        case idx, midi, beat, string, fret
        case durationBeats = "duration_beats"
        case noteName = "note_name"
    }

    init(id: UUID = UUID(), idx: Int, midi: Int, beat: Double,
         durationBeats: Double? = nil, string: Int? = nil, fret: Int? = nil, noteName: String? = nil) {
        self.id = id
        self.idx = idx
        self.midi = midi
        self.beat = beat
        self.durationBeats = durationBeats
        self.string = string
        self.fret = fret
        self.noteName = noteName
    }

    /// Anzuzeigende Lage: bevorzugt die gespeicherte/erkannte Saite+Bund,
    /// sonst der naive Vorschlag aus der Tonhöhe.
    var displayPosition: (string: Int, fret: Int)? {
        if let s = string, let f = fret { return (s, f) }
        return BassIntro.suggestStringFret(forMidi: midi)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        idx = try c.decode(Int.self, forKey: .idx)
        midi = try c.decode(Int.self, forKey: .midi)
        beat = try c.decode(Double.self, forKey: .beat)
        durationBeats = try? c.decode(Double.self, forKey: .durationBeats)
        string = try? c.decode(Int.self, forKey: .string)
        fret = try? c.decode(Int.self, forKey: .fret)
        noteName = try? c.decode(String.self, forKey: .noteName)
    }
}

/// Payload zum Schreiben nach `song_intros` (mit song_id + idx).
struct IntroNoteWrite: Encodable {
    let song_id: String
    let idx: Int
    let midi: Int
    let beat: Double
    let duration_beats: Double?
    let string: Int?
    let fret: Int?
    let note_name: String?
}

/// Bass-Helfer: klingende MIDI-Konvention für 5-Saiter
/// (open B0/E1/A1/D2/G2 = 23/28/33/38/43).
enum BassIntro {
    static let openMidi: [Int: Int] = [1: 23, 2: 28, 3: 33, 4: 38, 5: 43]   // 1=B … 5=G
    static let stringName: [Int: String] = [1: "B", 2: "E", 3: "A", 4: "D", 5: "G"]
    private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    static func midi(forFrequency f: Double) -> Int {
        Int((69.0 + 12.0 * log2(f / 440.0)).rounded())
    }

    static func frequency(forMidi m: Int) -> Double {
        440.0 * pow(2.0, (Double(m) - 69.0) / 12.0)
    }

    static func noteName(forMidi m: Int) -> String {
        let pc = ((m % 12) + 12) % 12
        let octave = m / 12 - 1
        return "\(names[pc])\(octave)"
    }

    /// Vorschlag Saite/Bund: kleinste sinnvolle Lage (höchste offene Saite ≤ midi).
    static func suggestStringFret(forMidi m: Int) -> (string: Int, fret: Int)? {
        for s in [5, 4, 3, 2, 1] {
            guard let open = openMidi[s] else { continue }
            let fret = m - open
            if fret >= 0 && fret <= 20 { return (s, fret) }
        }
        return nil
    }

    static func midi(string: Int, fret: Int) -> Int {
        (openMidi[string] ?? 23) + fret
    }

    /// Weist einer ganzen Tonfolge Saite/Bund zu und **minimiert die
    /// Bundabstände** zwischen aufeinanderfolgenden Tönen (dynamische
    /// Programmierung). Nil für Töne außerhalb des Griffbereichs.
    static func optimalPositions(forMidis midis: [Int], maxFret: Int = 17) -> [(string: Int, fret: Int)?] {
        let n = midis.count
        guard n > 0 else { return [] }
        // Kandidaten je Ton.
        let cands: [[(s: Int, f: Int)]] = midis.map { m in
            var cs: [(Int, Int)] = []
            for s in 1...5 {
                if let open = openMidi[s] {
                    let f = m - open
                    if f >= 0 && f <= maxFret { cs.append((s, f)) }
                }
            }
            return cs
        }
        let INF = Double.greatestFiniteMagnitude
        var dp = cands.map { $0.map { _ in INF } }
        var back = cands.map { $0.map { _ in -1 } }
        for (j, c) in cands[0].enumerated() { dp[0][j] = Double(c.f) * 0.1 }  // tiefe Startlage bevorzugen
        if n > 1 {
            for i in 1..<n {
                for (j, c) in cands[i].enumerated() {
                    if cands[i - 1].isEmpty {
                        dp[i][j] = Double(c.f) * 0.1   // Neustart nach Lücke
                        continue
                    }
                    var best = INF, bestK = -1
                    for (k, pc) in cands[i - 1].enumerated() where dp[i - 1][k] != INF {
                        // primär Bundabstand, leichte Straffung für Saitenwechsel + hohe Lagen
                        let move = abs(Double(c.f - pc.f)) + 0.25 * abs(Double(c.s - pc.s)) + Double(c.f) * 0.02
                        if dp[i - 1][k] + move < best { best = dp[i - 1][k] + move; bestK = k }
                    }
                    dp[i][j] = best; back[i][j] = bestK
                }
            }
        }
        var result = [(string: Int, fret: Int)?](repeating: nil, count: n)
        guard let last = (0..<n).reversed().first(where: { !cands[$0].isEmpty }) else { return result }
        var jBest = 0, cBest = INF
        for (j, _) in cands[last].enumerated() where dp[last][j] < cBest { cBest = dp[last][j]; jBest = j }
        var i = last, j = jBest
        while i >= 0, j >= 0 {
            let c = cands[i][j]
            result[i] = (c.s, c.f)
            let pj = back[i][j]
            i -= 1
            if i < 0 || pj < 0 { break }
            j = pj
        }
        // Lücken (Neustarts / unabgedeckte Töne) unabhängig mit tiefster Lage füllen.
        for k in 0..<n where result[k] == nil && !cands[k].isEmpty {
            if let c = cands[k].min(by: { $0.f < $1.f }) { result[k] = (c.s, c.f) }
        }
        return result
    }

    /// Griffbrett-Position (für die Bass-Sample-Wiedergabe der Griffbrett-Übung).
    /// Mappt die Intro-Saiten (1=B…5=G) auf `BassString` (g=0…b=4).
    static func fretPosition(forMidi m: Int) -> FretPosition {
        let sf = suggestStringFret(forMidi: m) ?? (string: 2, fret: max(0, m - 28))
        let map: [Int: BassString] = [1: .b, 2: .e, 3: .a, 4: .d, 5: .g]
        return FretPosition(string: map[sf.string] ?? .e, fret: sf.fret)
    }
}
