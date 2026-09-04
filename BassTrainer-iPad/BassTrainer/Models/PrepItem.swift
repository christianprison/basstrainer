import Foundation

/// Bausteintyp einer Auftritts-Vorbereitung.
enum PrepType: String, Codable, CaseIterable, Identifiable {
    case start      // Anfang / ersten Ton treffen
    case loop       // Passage im Loop mit steigendem Tempo
    case section    // bestimmte Passage / Lage sicher spielen
    case cue        // Merk-/Cue-Karte (Text), z. B. Absprache, Verwechslungsgefahr

    var id: String { rawValue }

    var label: String {
        switch self {
        case .start:   return "Anfang / Ton treffen"
        case .loop:    return "Loop + Tempo"
        case .section: return "Passage / Lage"
        case .cue:     return "Merk-Karte"
        }
    }

    var systemImage: String {
        switch self {
        case .start:   return "target"
        case .loop:    return "speedometer"
        case .section: return "scope"
        case .cue:     return "lightbulb.fill"
        }
    }
}

/// Ein Baustein der Auftritts-Vorbereitung: an einen Song gebunden, mit Typ,
/// freier Notiz und Reihenfolge. Persistiert pro User in Supabase (`prep_items`).
struct PrepItem: Identifiable, Codable, Equatable {
    var id: String          // UUID (clientseitig vergeben)
    var songID: String
    var type: PrepType
    var note: String
    var ord: Int
    var startBar: Int?      // optional an eine Taktstelle gebunden …
    var endBar: Int?        // … dann startet Antippen den Loop genau dieser Passage

    /// Ist der Baustein an einen Taktbereich gebunden (→ Loop der Passage)?
    var bars: (start: Int, end: Int)? {
        guard let s = startBar, let e = endBar, e >= s else { return nil }
        return (s, e)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case songID = "song_id"
        case type, note, ord
        case startBar = "start_bar"
        case endBar = "end_bar"
    }

    init(id: String, songID: String, type: PrepType, note: String, ord: Int,
         startBar: Int? = nil, endBar: Int? = nil) {
        self.id = id; self.songID = songID; self.type = type; self.note = note
        self.ord = ord; self.startBar = startBar; self.endBar = endBar
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        songID = try c.decode(String.self, forKey: .songID)
        type = (try? c.decode(PrepType.self, forKey: .type)) ?? .cue
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        ord = (try? c.decode(Int.self, forKey: .ord)) ?? 0
        startBar = try? c.decode(Int.self, forKey: .startBar)
        endBar = try? c.decode(Int.self, forKey: .endBar)
    }
}
