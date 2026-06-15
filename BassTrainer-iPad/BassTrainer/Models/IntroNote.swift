import Foundation

/// Ein Ton eines Song-Anfangs. Gelesen aus `song_intro_public`,
/// geschrieben (Kurator) nach `song_intros`.
struct IntroNote: Identifiable, Codable, Equatable {
    var id = UUID()            // nur clientseitig
    var idx: Int
    var midi: Int              // klingende Tonhöhe
    var beat: Double           // Viertel ab Downbeat (Auftakt negativ)
    var durationBeats: Double?
    var string: Int?           // 1=E … 4=G (klingende Konvention)
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

/// Bass-Helfer: klingende MIDI-Konvention (open E1/A1/D2/G2 = 28/33/38/43).
enum BassIntro {
    static let openMidi: [Int: Int] = [1: 28, 2: 33, 3: 38, 4: 43]   // 1=E … 4=G
    static let stringName: [Int: String] = [1: "E", 2: "A", 3: "D", 4: "G"]
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
        for s in [4, 3, 2, 1] {
            guard let open = openMidi[s] else { continue }
            let fret = m - open
            if fret >= 0 && fret <= 20 { return (s, fret) }
        }
        return nil
    }

    static func midi(string: Int, fret: Int) -> Int {
        (openMidi[string] ?? 28) + fret
    }
}
