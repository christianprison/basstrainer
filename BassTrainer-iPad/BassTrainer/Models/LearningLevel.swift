import SwiftUI

struct LearningLevel: Identifiable {
    let id: Int
    let name: String
    let description: String
    let notes: [NoteName]
    let frets: [Int]
    let targetBalance: Double
    let color: Color

    static let levels: [LearningLevel] = [
        LearningLevel(
            id: 1,
            name: "Level 1: First Frets",
            description: "Learn natural notes on frets 0, 3, 5, 7 with 50% balance",
            notes: NoteName.naturalNotes,
            frets: [0, 3, 5, 7],
            targetBalance: 50,
            color: Color(red: 0.9, green: 0.75, blue: 0.2)
        ),
        LearningLevel(
            id: 2,
            name: "Level 2: Add Fret 9",
            description: "Natural notes on frets 3, 5, 7, 9 with 60% balance",
            notes: NoteName.naturalNotes,
            frets: [3, 5, 7, 9],
            targetBalance: 60,
            color: Color(red: 0.6, green: 0.8, blue: 0.2)
        ),
        LearningLevel(
            id: 3,
            name: "Level 3: Add Fret 12",
            description: "Natural notes on frets 3, 5, 7, 9, 12 with 70% balance",
            notes: NoteName.naturalNotes,
            frets: [3, 5, 7, 9, 12],
            targetBalance: 70,
            color: Color(red: 0.2, green: 0.8, blue: 0.4)
        ),
        LearningLevel(
            id: 4,
            name: "Level 4: Add Fret 15",
            description: "Natural notes on frets 3, 5, 7, 9, 12, 15 with 80% balance",
            notes: NoteName.naturalNotes,
            frets: [3, 5, 7, 9, 12, 15],
            targetBalance: 80,
            color: Color(red: 0.2, green: 0.7, blue: 0.6)
        ),
        LearningLevel(
            id: 5,
            name: "Level 5: Add Fret 17",
            description: "Natural notes on frets 3, 5, 7, 9, 12, 15, 17 with 90% balance",
            notes: NoteName.naturalNotes,
            frets: [3, 5, 7, 9, 12, 15, 17],
            targetBalance: 90,
            color: Color(red: 0.2, green: 0.6, blue: 0.8)
        ),
        LearningLevel(
            id: 6,
            name: "Level 6: Add Sharps/Flats",
            description: "All notes on frets 3, 5, 7, 9, 12, 15, 17, 19 with 50% balance",
            notes: NoteName.allNotes,
            frets: [3, 5, 7, 9, 12, 15, 17, 19],
            targetBalance: 50,
            color: Color(red: 0.3, green: 0.4, blue: 0.9)
        ),
        LearningLevel(
            id: 7,
            name: "Level 7: Add Fret 21",
            description: "All notes on frets 3, 5, 7, 9, 12, 15, 17, 19, 21 with 70% balance",
            notes: NoteName.allNotes,
            frets: [3, 5, 7, 9, 12, 15, 17, 19, 21],
            targetBalance: 70,
            color: Color(red: 0.4, green: 0.3, blue: 0.9)
        ),
        LearningLevel(
            id: 8,
            name: "Level 8: Master All Frets",
            description: "All notes on frets 3, 5, 7, 9, 12, 15, 17, 19, 21, 24 with 90% balance",
            notes: NoteName.allNotes,
            frets: [3, 5, 7, 9, 12, 15, 17, 19, 21, 24],
            targetBalance: 90,
            color: Color(red: 0.5, green: 0.2, blue: 0.9)
        ),
    ]

    /// Get all valid positions for this level
    var allValidPositions: [FretPosition] {
        var positions: [FretPosition] = []
        for string in BassString.allCases {
            for fret in frets {
                let position = FretPosition(string: string, fret: fret)
                if notes.contains(position.note) {
                    positions.append(position)
                }
            }
        }
        return positions
    }
}
