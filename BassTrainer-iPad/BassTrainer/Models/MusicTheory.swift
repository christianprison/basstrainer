import Foundation

// MARK: - Note Names

enum NoteName: String, CaseIterable, Identifiable, Codable {
    case c = "C"
    case cSharp = "C#"
    case d = "D"
    case dSharp = "D#"
    case e = "E"
    case f = "F"
    case fSharp = "F#"
    case g = "G"
    case gSharp = "G#"
    case a = "A"
    case aSharp = "A#"
    case b = "B"

    var id: String { rawValue }

    static let naturalNotes: [NoteName] = [.c, .d, .e, .f, .g, .a, .b]
    static let allNotes: [NoteName] = Array(allCases)

    /// Keyboard shortcut key for this note (lowercase)
    var keyboardKey: Character? {
        switch self {
        case .c: return "c"
        case .d: return "d"
        case .e: return "e"
        case .f: return "f"
        case .g: return "g"
        case .a: return "a"
        case .b: return "b"
        default: return nil
        }
    }
}

// MARK: - Bass Strings

enum BassString: Int, CaseIterable, Identifiable {
    case g = 0
    case d = 1
    case a = 2
    case e = 3
    case b = 4

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .g: return "G"
        case .d: return "D"
        case .a: return "A"
        case .e: return "E"
        case .b: return "B"
        }
    }

    /// The open string note pattern (chromatic from open string)
    var notePattern: [NoteName] {
        switch self {
        case .g: return [.g, .gSharp, .a, .aSharp, .b, .c, .cSharp, .d, .dSharp, .e, .f, .fSharp]
        case .d: return [.d, .dSharp, .e, .f, .fSharp, .g, .gSharp, .a, .aSharp, .b, .c, .cSharp]
        case .a: return [.a, .aSharp, .b, .c, .cSharp, .d, .dSharp, .e, .f, .fSharp, .g, .gSharp]
        case .e: return [.e, .f, .fSharp, .g, .gSharp, .a, .aSharp, .b, .c, .cSharp, .d, .dSharp]
        case .b: return [.b, .c, .cSharp, .d, .dSharp, .e, .f, .fSharp, .g, .gSharp, .a, .aSharp]
        }
    }

    /// Base frequency of the open string (Hz)
    var openFrequency: Double {
        switch self {
        case .g: return 196.00  // G3
        case .d: return 146.83  // D3
        case .a: return 110.00  // A2
        case .e: return 82.41   // E2
        case .b: return 61.74   // B1
        }
    }
}

// MARK: - Fret Position

struct FretPosition: Equatable, Hashable {
    let string: BassString
    let fret: Int

    var note: NoteName {
        string.notePattern[fret % 12]
    }

    /// Audio sample key (e.g., "G_003")
    var audioKey: String {
        "\(string.name)_\(String(format: "%03d", min(fret, 12)))"
    }

    /// Frequency in Hz for this position
    var frequency: Double {
        string.openFrequency * pow(2.0, Double(fret) / 12.0)
    }

    /// Response time tracking key
    var trackingKey: String {
        "\(note.rawValue)-\(string.rawValue)-\(fret)"
    }
}

// MARK: - Helper

func getNoteAtPosition(stringIndex: Int, fret: Int) -> NoteName? {
    guard let string = BassString(rawValue: stringIndex) else { return nil }
    return string.notePattern[fret % 12]
}
