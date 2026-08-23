import Foundation

/// Eine Technik-Übung für den geführten Ablauf „Vorspielen → Einzähler →
/// Nachspielen". `positions` ist die Tonfolge (ein Ton pro Beat, auf und ab),
/// `bpm` das Zieltempo. Beim Nachspielen bewertet die App Tonhöhe und Timing.
struct TechniqueExercise: Identifiable, Equatable {
    let id: String
    let name: String
    let bpm: Int
    let focus: String        // „Was übe ich?" – kurzes Ziel
    let howTo: String        // konkrete Anleitung
    let systemImage: String
    let logLabel: String     // Kategorie fürs Übungs-Log
    let positions: [FretPosition]

    static func == (l: TechniqueExercise, r: TechniqueExercise) -> Bool { l.id == r.id }
}

private func p(_ s: BassString, _ f: Int) -> FretPosition { FretPosition(string: s, fret: f) }

/// Bibliothek der Technik-Übungen + Tages-Rotation (nicht jeden Tag dieselben).
enum TechniqueLibrary {

    // MARK: Warm-ups (Finger-Unabhängigkeit)

    static let warmups: [TechniqueExercise] = [
        TechniqueExercise(
            id: "warm-chromatic", name: "Chromatic Crawl", bpm: 70,
            focus: "Finger 1-2-3-4 sauber pro Saite",
            howTo: "Auf jeder Saite die Bünde 5-6-7-8 mit Finger 1-2-3-4 nacheinander. Ein Ton pro Klick, gleichmäßig.",
            systemImage: "flame.fill", logLabel: "Warm-up",
            positions: ([.b, .e, .a, .d, .g] as [BassString]).flatMap { s in (5...8).map { p(s, $0) } }
        ),
        TechniqueExercise(
            id: "warm-spider", name: "Spider", bpm: 66,
            focus: "Finger-Unabhängigkeit über Saitenpaare",
            howTo: "Über benachbarte Saiten: tief Bund 5, hoch 6, tief 7, hoch 8. Finger einzeln setzen, nicht rutschen.",
            systemImage: "flame.fill", logLabel: "Warm-up",
            positions: {
                let lh: [BassString] = [.b, .e, .a, .d, .g]
                var r: [FretPosition] = []
                for i in 0..<(lh.count - 1) {
                    r += [p(lh[i], 5), p(lh[i + 1], 6), p(lh[i], 7), p(lh[i + 1], 8)]
                }
                return r
            }()
        ),
    ]

    // MARK: Technik (Oktaven, Skalen, Saitenwechsel)

    static let techniques: [TechniqueExercise] = [
        TechniqueExercise(
            id: "tech-octaves", name: "Oktaven", bpm: 80,
            focus: "Oktavgriff sicher greifen und treffen",
            howTo: "Grundton, dann Oktave (2 Saiten höher, 2 Bünde höher). Über B-E-A-Saite hoch. Sauber, nicht hetzen.",
            systemImage: "bolt.fill", logLabel: "Oktaven",
            positions: [p(.b, 5), p(.a, 7), p(.e, 5), p(.d, 7), p(.a, 5), p(.g, 7)]
        ),
        TechniqueExercise(
            id: "tech-major", name: "Dur-Tonleiter (D)", bpm: 76,
            focus: "Dur-Fingersatz über eine Oktave",
            howTo: "D-Dur eine Oktave hoch und wieder runter: D-E-F#-G-A-H-C#-D. Jeder Ton auf den Klick.",
            systemImage: "music.quarternote.3", logLabel: "Tonleiter",
            positions: [p(.a, 5), p(.a, 7), p(.d, 4), p(.d, 5), p(.d, 7), p(.g, 4), p(.g, 6), p(.g, 7)]
        ),
        TechniqueExercise(
            id: "tech-strings", name: "Saitenwechsel", bpm: 72,
            focus: "Sauberer Wechsel über alle Saiten",
            howTo: "Ein Ton pro Saite (Bund 5) von tief nach hoch und zurück. Rechte Hand: gleichmäßig wechseln.",
            systemImage: "arrow.left.arrow.right", logLabel: "Saitenwechsel",
            positions: [p(.b, 5), p(.e, 5), p(.a, 5), p(.d, 5), p(.g, 5)]
        ),
    ]

    // MARK: Pentatonik (mit klarer Übe-Ansage)

    static let pentatonics: [TechniqueExercise] = [
        TechniqueExercise(
            id: "penta-a-minor", name: "Moll-Pentatonik (Am)", bpm: 74,
            focus: "Moll-Pentatonik-Box rauf und runter",
            howTo: "A-Moll-Pentatonik (A-C-D-E-G): die Box ab Bund 5 auf E-A-D-G hoch und wieder runter spielen. So sitzt die Shape in den Fingern.",
            systemImage: "square.grid.3x3.fill", logLabel: "Pentatonic Shapes",
            positions: [p(.e, 5), p(.e, 8), p(.a, 5), p(.a, 7), p(.d, 5), p(.d, 7), p(.g, 5), p(.g, 7)]
        ),
        TechniqueExercise(
            id: "penta-c-major", name: "Dur-Pentatonik (C)", bpm: 74,
            focus: "Dur-Pentatonik-Box rauf und runter",
            howTo: "C-Dur-Pentatonik (C-D-E-G-A): ab A-Saite Bund 3 die Box hoch und runter. Grundton C bewusst hören.",
            systemImage: "square.grid.3x3.fill", logLabel: "Pentatonic Shapes",
            positions: [p(.a, 3), p(.a, 5), p(.d, 2), p(.d, 5), p(.d, 7), p(.g, 4), p(.g, 5), p(.g, 7)]
        ),
    ]

    /// Tagesnummer (wechselt täglich) als Rotations-Seed.
    static var dayNumber: Int { Int(Date().timeIntervalSince1970 / 86400) }

    static func warmup(seed: Int) -> TechniqueExercise {
        warmups[((seed % warmups.count) + warmups.count) % warmups.count]
    }

    static func pentatonic(seed: Int) -> TechniqueExercise {
        pentatonics[((seed % pentatonics.count) + pentatonics.count) % pentatonics.count]
    }

    /// Technik-Übungen ab dem Tages-Seed rotiert (distinct, in Reihenfolge).
    static func techniquesRotated(seed: Int) -> [TechniqueExercise] {
        guard !techniques.isEmpty else { return [] }
        let start = ((seed % techniques.count) + techniques.count) % techniques.count
        return (0..<techniques.count).map { techniques[(start + $0) % techniques.count] }
    }
}
