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

    enum CodingKeys: String, CodingKey {
        case id
        case songID = "song_id"
        case type, note, ord
    }
}
