import Foundation

/// Welche Ansicht ein Menü-Blatt startet.
enum MenuMode {
    case fretboard          // klassischer Griffbrett-Trainer (ContentView)
    case tuner              // Pitch-Detection / Noten-Erkennung (TunerView)
    case precisionOctaves   // Oktaven nach Metronom
    case songsList          // Aktuelle Setlist (setlist_public)
    case repertoireList     // Alle Songs (Tabelle songs)
    case introQuiz          // Songanfänge merken (Abruf-Übung)
    case introRecorder      // Kurator: Song-Anfänge einspielen → DB
    case curatorSettings    // Kurator-Status / eigene uid
    case help               // In-App-Hilfe
    case practiceClass      // Übungskapitel: alle markierten Stellen einer Kategorie
    case placeholder        // "Kommt bald"
}

/// Ein Menüeintrag: entweder Kategorie (mit `children`) oder Übung (mit `mode`).
struct MenuItem: Identifiable, Hashable {
    let id: String
    let label: String
    let description: String?
    var children: [MenuItem]? = nil
    var mode: MenuMode? = nil
    var practiceReason: PracticeReason? = nil   // nur für mode == .practiceClass

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
                MenuItem(id: "uebung-lagenwechsel", label: "Lagenwechsel", description: "Alle markierten Lagenwechsel durchüben", mode: .practiceClass, practiceReason: .shift),
                MenuItem(id: "uebung-tonsicherheit", label: "Tonsicherheit", description: "Alle markierten Tonsicherheits-Stellen durchüben", mode: .practiceClass, practiceReason: .notes),
                MenuItem(id: "uebung-sonstiges", label: "Sonstiges", description: "Alle übrigen markierten Stellen durchüben", mode: .practiceClass, practiceReason: .other),
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
                MenuItem(id: "uebung-geschwindigkeit", label: "Geschwindigkeit", description: "Alle markierten Geschwindigkeits-Stellen durchüben", mode: .practiceClass, practiceReason: .speed),
                MenuItem(id: "uebung-praezision", label: "Präzision", description: "Alle markierten Präzisions-Stellen durchüben", mode: .practiceClass, practiceReason: .precision),
                MenuItem(id: "uebung-timing", label: "Timing", description: "Alle markierten Timing-Stellen durchüben", mode: .practiceClass, practiceReason: .timing),
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
            label: "Repertoire",
            description: "Komplette Songs üben",
            children: [
                MenuItem(id: "aktuelle-setlist", label: "Aktuelle Setlist", description: "Aktuelle Setlist – zum Mitspielen", mode: .songsList),
                MenuItem(id: "repertoire", label: "Alle Songs", description: "Alle Songs – zum Mitspielen", mode: .repertoireList),
                MenuItem(id: "songanfaenge-merken", label: "Songanfänge merken", description: "Zufälliger Songanfang nach 2-Takt-Einzähler", mode: .introQuiz),
            ]
        ),
        MenuItem(
            id: "werkzeuge",
            label: "Werkzeuge",
            description: "Hilfsmittel rund ums Üben",
            children: [
                MenuItem(id: "pitch-detection", label: "Noten-Erkennung", description: "Live-Tonhöhe vom (USB-)Audio-Eingang", mode: .tuner),
                MenuItem(id: "intro-recorder", label: "Intro einspielen", description: "Song-Anfänge aufnehmen & in die DB schreiben (Kurator)", mode: .introRecorder),
                MenuItem(id: "einstellungen", label: "Einstellungen", description: "Kurator-Status / Geräte-ID (uid)", mode: .curatorSettings),
                MenuItem(id: "hilfe", label: "Hilfe", description: "Troubleshooting & Bedien-Hinweise", mode: .help),
            ]
        ),
    ]
}
