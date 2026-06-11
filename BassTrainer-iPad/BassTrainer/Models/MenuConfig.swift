import Foundation

/// Welche Ansicht ein Menü-Blatt startet.
enum MenuMode {
    case fretboard          // klassischer Griffbrett-Trainer (ContentView)
    case tuner              // Pitch-Detection / Noten-Erkennung (TunerView)
    case precisionOctaves   // Oktaven nach Metronom (Schritt 2)
    case placeholder        // "Kommt bald"
}

/// Ein Menüeintrag: entweder Kategorie (mit `children`) oder Übung (mit `mode`).
struct MenuItem: Identifiable, Hashable {
    let id: String
    let label: String
    let description: String?
    var children: [MenuItem]? = nil
    var mode: MenuMode? = nil

    static func == (lhs: MenuItem, rhs: MenuItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Menüstruktur — spiegelt die Web-Version (lib/menu-config.ts) plus einen
/// "Werkzeuge"-Bereich für die native Noten-Erkennung.
enum MenuConfig {
    static let main: [MenuItem] = [
        MenuItem(
            id: "griffbrett",
            label: "Griffbrett",
            description: "Notenerkennung & Navigation auf dem Griffbrett",
            children: [
                MenuItem(id: "quinten", label: "Quinten", description: "Quintenzirkel auf dem Griffbrett", mode: .placeholder),
                MenuItem(id: "quarten", label: "Quarten", description: "Quartensprünge üben", mode: .placeholder),
                MenuItem(id: "griffbrett-trainer", label: "Griffbrett", description: "Das klassische BassTrainer-Training", mode: .fretboard),
            ]
        ),
        MenuItem(
            id: "praezision",
            label: "Präzision",
            description: "Anschlag & Timing",
            children: [
                MenuItem(id: "oktaven", label: "Oktaven", description: "Oktaven nach Metronom – progressives Tempo", mode: .precisionOctaves),
                MenuItem(id: "pick", label: "Pick", description: "Präzision mit Plektrum", mode: .placeholder),
                MenuItem(id: "fingered", label: "Fingered", description: "Präzision mit Fingern", mode: .placeholder),
            ]
        ),
        MenuItem(
            id: "improvisation",
            label: "Improvisation",
            description: "Skalen & freies Spiel",
            children: [
                MenuItem(id: "pentatonic-shapes", label: "Pentatonic Shapes", description: "Pentatonik-Patterns über das Griffbrett", mode: .placeholder),
            ]
        ),
        MenuItem(
            id: "songs",
            label: "Songs",
            description: "Komplette Songs üben",
            children: [
                MenuItem(id: "kitn", label: "Killing in the Name of", description: "Rage Against the Machine", mode: .placeholder),
                MenuItem(id: "word-up", label: "Word up", description: "Cameo", mode: .placeholder),
            ]
        ),
        MenuItem(
            id: "werkzeuge",
            label: "Werkzeuge",
            description: "Hilfsmittel rund ums Üben",
            children: [
                MenuItem(id: "pitch-detection", label: "Noten-Erkennung", description: "Live-Tonhöhe vom (USB-)Audio-Eingang", mode: .tuner),
            ]
        ),
    ]
}
