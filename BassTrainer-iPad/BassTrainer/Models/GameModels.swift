import Foundation

// MARK: - Game Statistics

struct GameStats {
    var correct: Int = 0
    var incorrect: Int = 0
    var streak: Int = 0
    var bestStreak: Int = 0
    var totalTime: TimeInterval = 0
    var averageTime: TimeInterval = 0
    var level: Int = 1
    var levelProgress: Double = 0
}

// MARK: - Response Time Tracking

struct ResponseTimeEntry {
    var times: [TimeInterval] = []
    var average: TimeInterval = 0
    var count: Int = 0
    var wrongCount: Int = 0

    mutating func addCorrectResponse(time: TimeInterval) {
        times.append(time)
        if times.count > 10 {
            times = Array(times.suffix(10))
        }
        average = times.reduce(0, +) / Double(times.count)
        count += 1
    }

    mutating func addWrongResponse() {
        let penaltyTime: TimeInterval = 10.0
        times.append(penaltyTime)
        if times.count > 10 {
            times = Array(times.suffix(10))
        }
        average = times.reduce(0, +) / Double(times.count)
        wrongCount += 1
    }
}

// MARK: - Answer Feedback

enum AnswerFeedback {
    case correct
    case incorrect
}

// MARK: - Position Performance Data (for chart display)

struct PositionPerformance: Identifiable {
    let id = UUID()
    let string: BassString
    let fret: Int
    let note: NoteName
    let average: TimeInterval
    let count: Int

    var sortKey: Int {
        fret * 100 + (4 - string.rawValue)
    }
}

// MARK: - Confetti Intensity

enum ConfettiIntensity {
    case small
    case medium
    case large

    var particleCount: Int {
        switch self {
        case .small: return 30
        case .medium: return 60
        case .large: return 100
        }
    }
}

// MARK: - Achievement Event

struct AchievementEvent: Identifiable {
    let id = UUID()
    let message: String
    let intensity: ConfettiIntensity
}
