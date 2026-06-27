import SwiftUI

/// Grund, warum eine Stelle zum Üben markiert wurde.
enum PracticeReason: String, Codable, CaseIterable, Identifiable {
    case speed       // Geschwindigkeit
    case precision   // Präzision
    case timing      // Timing
    case shift       // Lagenwechsel
    case notes       // Tonsicherheit (Töne sitzen noch nicht)
    case other       // Sonstiges

    var id: String { rawValue }

    var label: String {
        switch self {
        case .speed:     return "Geschwindigkeit"
        case .precision: return "Präzision"
        case .timing:    return "Timing"
        case .shift:     return "Lagenwechsel"
        case .notes:     return "Tonsicherheit"
        case .other:     return "Sonstiges"
        }
    }

    var systemImage: String {
        switch self {
        case .speed:     return "hare"
        case .precision: return "scope"
        case .timing:    return "metronome"
        case .shift:     return "arrow.left.arrow.right"
        case .notes:     return "music.note"
        case .other:     return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .speed:     return .red
        case .precision: return .orange
        case .timing:    return .blue
        case .shift:     return .purple
        case .notes:     return .green
        case .other:     return .gray
        }
    }
}

/// Wie die markierte Stelle geübt werden soll.
enum PracticeMode: String, Codable, CaseIterable, Identifiable {
    case loop        // isoliert loopen, langsam → schneller (Präzision)
    case context     // im Zusammenhang, mit Anlauf aus dem Teil davor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .loop:    return "Im Loop"
        case .context: return "Im Zusammenhang"
        }
    }

    var shortLabel: String {
        switch self {
        case .loop:    return "Loop"
        case .context: return "Zusammenhang"
        }
    }

    var systemImage: String {
        switch self {
        case .loop:    return "repeat"
        case .context: return "arrow.turn.down.right"
        }
    }
}

/// Eine markierte Übe-Stelle (Taktbereich + Grund + Modus). Wird aus
/// `practice_markers` (Supabase) gelesen/geschrieben; lokaler Cache als Fallback.
struct PracticeMarker: Identifiable, Codable, Equatable {
    var id = UUID()
    let songID: String
    let startBar: Int
    let endBar: Int
    let reason: PracticeReason
    var mode: PracticeMode
    var note: String?

    func contains(bar: Int) -> Bool { bar >= startBar && bar <= endBar }

    enum CodingKeys: String, CodingKey {
        case id, reason, mode, note
        case songID = "song_id"
        case startBar = "start_bar"
        case endBar = "end_bar"
    }

    init(id: UUID = UUID(), songID: String, startBar: Int, endBar: Int,
         reason: PracticeReason, mode: PracticeMode, note: String? = nil) {
        self.id = id
        self.songID = songID
        self.startBar = startBar
        self.endBar = endBar
        self.reason = reason
        self.mode = mode
        self.note = note
    }

    // Robust gegen fehlende Spalten (z. B. `mode` vor der Migration → Default loop).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        songID = try c.decode(String.self, forKey: .songID)
        startBar = try c.decode(Int.self, forKey: .startBar)
        endBar = try c.decode(Int.self, forKey: .endBar)
        reason = (try? c.decode(PracticeReason.self, forKey: .reason)) ?? .other
        mode = (try? c.decode(PracticeMode.self, forKey: .mode)) ?? .loop
        note = try? c.decode(String.self, forKey: .note)
    }
}

/// Payload zum Anlegen (ohne id/user_id — `user_id` setzt die DB per auth.uid()).
struct PracticeMarkerInsert: Encodable {
    let song_id: String
    let start_bar: Int
    let end_bar: Int
    let reason: String
    let mode: String
    let note: String?
}
