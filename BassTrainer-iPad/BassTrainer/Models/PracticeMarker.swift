import SwiftUI

/// Grund, warum eine Stelle zum Üben markiert wurde.
enum PracticeReason: String, Codable, CaseIterable, Identifiable {
    case speed       // Geschwindigkeit
    case precision   // Präzision
    case timing      // Timing
    case shift       // Lagenwechsel
    case other       // Sonstiges

    var id: String { rawValue }

    var label: String {
        switch self {
        case .speed:     return "Geschwindigkeit"
        case .precision: return "Präzision"
        case .timing:    return "Timing"
        case .shift:     return "Lagenwechsel"
        case .other:     return "Sonstiges"
        }
    }

    var systemImage: String {
        switch self {
        case .speed:     return "hare"
        case .precision: return "scope"
        case .timing:    return "metronome"
        case .shift:     return "arrow.left.arrow.right"
        case .other:     return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .speed:     return .red
        case .precision: return .orange
        case .timing:    return .blue
        case .shift:     return .purple
        case .other:     return .gray
        }
    }
}

/// Eine markierte Übe-Stelle (Taktbereich + Grund), lokal am Gerät gespeichert.
struct PracticeMarker: Identifiable, Codable, Equatable {
    var id = UUID()
    let songID: String
    let startBar: Int
    let endBar: Int
    let reason: PracticeReason
    var createdAt = Date()

    func contains(bar: Int) -> Bool { bar >= startBar && bar <= endBar }
}
