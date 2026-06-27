import Combine
import SwiftUI

@MainActor
final class GameViewModel: ObservableObject {
    // MARK: - Published State

    @Published var isPlaying = false
    @Published var currentPosition: FretPosition?
    @Published var currentNote: NoteName = .c
    @Published var feedback: AnswerFeedback?
    @Published var gameStats = GameStats()
    @Published var responseTimes: [String: ResponseTimeEntry] = [:]
    @Published var achievements: Set<String> = []
    @Published var levelFeedback: String?
    @Published var gameComplete = false
    @Published var showConfetti = false
    @Published var confettiIntensity: ConfettiIntensity = .medium
    @Published var achievementMessage: String?
    @Published var timeLeft: TimeInterval = 0

    // MARK: - Dependencies

    let audioEngine = AudioEngine()

    // MARK: - Private State

    private var startTime: Date?
    private var gameStartTime: Date?
    private var recentNotes: [(note: NoteName, timestamp: Date)] = []
    private var metronomeTimer: Timer?
    private var beatCounter = 0
    private var roundTimer: Timer?
    private var feedbackTimer: Timer?

    // MARK: - Computed Properties

    var currentLevel: LearningLevel {
        LearningLevel.levels[min(gameStats.level - 1, LearningLevel.levels.count - 1)]
    }

    var balanceScore: Double {
        calculateBalanceScore(level: gameStats.level)
    }

    var levelProgress: (progress: Double, balanceReady: Bool) {
        getLevelProgress()
    }

    var attemptsProgress: (completed: Int, total: Int) {
        getAttemptsProgress()
    }

    var notePositionData: [PositionPerformance] {
        getNotePositionData(level: gameStats.level)
    }

    // MARK: - Initialization

    init() {
        Task {
            await audioEngine.preload()
        }
    }

    // MARK: - Game Controls

    func toggleGame() {
        if isPlaying {
            pauseGame()
        } else {
            startGame()
        }
    }

    func resetGame() {
        isPlaying = false
        stopGroove()
        roundTimer?.invalidate()
        roundTimer = nil
        feedbackTimer?.invalidate()
        feedbackTimer = nil
        gameStats = GameStats()
        responseTimes = [:]
        achievements = []
        recentNotes = []
        currentNote = .c
        currentPosition = nil
        feedback = nil
        gameComplete = false
        levelFeedback = nil
        gameStartTime = nil
        timeLeft = 0
    }

    // MARK: - Answer Submission

    func submitAnswer(_ answer: NoteName) {
        guard isPlaying, let position = currentPosition, feedback == nil else { return }

        let responseTime = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let isCorrect = answer == currentNote

        feedback = isCorrect ? .correct : .incorrect

        if isCorrect {
            audioEngine.playBassNote(position: position)
        }

        // Update response times
        let key = position.trackingKey
        var entry = responseTimes[key] ?? ResponseTimeEntry()
        if isCorrect {
            entry.addCorrectResponse(time: responseTime)
        } else {
            entry.addWrongResponse()
        }
        responseTimes[key] = entry

        // Update stats
        gameStats.correct += isCorrect ? 1 : 0
        gameStats.incorrect += isCorrect ? 0 : 1
        gameStats.streak = isCorrect ? gameStats.streak + 1 : 0
        gameStats.bestStreak = max(gameStats.bestStreak, gameStats.streak)
        if isCorrect {
            gameStats.totalTime += responseTime
            gameStats.averageTime = gameStats.correct > 0 ? gameStats.totalTime / Double(gameStats.correct) : 0
        }

        // Check achievements
        if isCorrect {
            checkAchievements(
                key: key,
                count: entry.count,
                note: currentNote,
                position: position
            )
        }

        // Check level progression
        if isCorrect && gameStats.level < 8 {
            let levelComplete = checkLevelCompletion(level: gameStats.level)
            if levelComplete {
                let nextLevel = gameStats.level + 1
                if nextLevel > 8 {
                    triggerConfetti(.large)
                    gameComplete = true
                    levelFeedback = "Geschafft! Du hast alle Level gemeistert!"
                    isPlaying = false
                    return
                } else {
                    gameStats.level = nextLevel
                    triggerConfetti(.medium)
                    audioEngine.playFanfare()
                    responseTimes = [:]
                    achievements = []
                    levelFeedback = "Willkommen bei \(LearningLevel.levels[nextLevel - 1].name)"
                }
            }
        }

        // Check groove start (after 200 total attempts)
        let totalAttempts = gameStats.correct + gameStats.incorrect
        if totalAttempts >= 200 && metronomeTimer == nil {
            startGroove()
        }

        // Start next round after brief delay — bei Fehlern länger sichtbar.
        let nextDelay = isCorrect ? 1.0 : 2.6
        feedbackTimer?.invalidate()
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: nextDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isPlaying, !self.gameComplete else { return }
                self.startNewRound()
            }
        }
    }

    // MARK: - Private Game Logic

    private func startGame() {
        if gameComplete {
            resetGame()
        }
        isPlaying = true
        gameStartTime = Date()
        startNewRound()
    }

    private func pauseGame() {
        isPlaying = false
        stopGroove()
        currentPosition = nil
        timeLeft = 0
        roundTimer?.invalidate()
        roundTimer = nil
        feedbackTimer?.invalidate()
        feedbackTimer = nil
    }

    private func startNewRound() {
        let position = generateAdaptivePosition()
        currentPosition = position
        currentNote = position.note
        feedback = nil
        timeLeft = 8.0
        startTime = Date()

        // Start countdown timer
        roundTimer?.invalidate()
        roundTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                guard let start = self.startTime else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.timeLeft = max(0, 8.0 - elapsed)
                if self.timeLeft <= 0 {
                    timer.invalidate()
                    // Time's up - count as wrong
                    if self.feedback == nil {
                        self.submitAnswer(.c == self.currentNote ? .d : .c) // Submit wrong answer
                    }
                }
            }
        }
    }

    // MARK: - Adaptive Position Generation

    private func generateAdaptivePosition() -> FretPosition {
        let level = currentLevel
        var validPositions: [(position: FretPosition, weight: Double)] = []

        for string in BassString.allCases {
            for fret in level.frets {
                let position = FretPosition(string: string, fret: fret)
                guard level.notes.contains(position.note) else { continue }

                let key = position.trackingKey
                let responseData = responseTimes[key]

                var weight: Double = 1.0
                if let data = responseData, data.count > 0 {
                    let maxTime = responseTimes.values
                        .filter { $0.count > 0 }
                        .map(\.average)
                        .max() ?? 2.0
                    let maxRef = max(maxTime, 2.0)
                    weight = max(0.1, data.average / maxRef) * 2.0
                } else {
                    weight = 2.0 // New positions get high weight
                }

                validPositions.append((position, weight))
            }
        }

        guard !validPositions.isEmpty else {
            // Fallback
            let fret = level.frets.randomElement() ?? 0
            let string = BassString.allCases.randomElement() ?? .a
            return FretPosition(string: string, fret: fret)
        }

        // Weighted random selection
        let totalWeight = validPositions.reduce(0.0) { $0 + $1.weight }
        var random = Double.random(in: 0..<totalWeight)

        for (position, weight) in validPositions {
            random -= weight
            if random <= 0 {
                return position
            }
        }

        return validPositions[0].position
    }

    // MARK: - Balance Score Calculation

    func calculateBalanceScore(level: Int) -> Double {
        guard level >= 1, level <= LearningLevel.levels.count else { return 0 }
        let lvl = LearningLevel.levels[level - 1]

        let relevantKeys = responseTimes.keys.filter { key in
            let parts = key.split(separator: "-")
            guard parts.count == 3,
                  let note = NoteName(rawValue: String(parts[0])),
                  let fret = Int(parts[2])
            else { return false }
            return lvl.notes.contains(note) && lvl.frets.contains(fret) && (responseTimes[key]?.count ?? 0) >= 3
        }

        guard relevantKeys.count >= 2 else { return 0 }

        let averages = relevantKeys.compactMap { key -> Double? in
            guard let entry = responseTimes[key] else { return nil }
            let recentTimes = Array(entry.times.suffix(50))
            return recentTimes.reduce(0, +) / Double(recentTimes.count)
        }

        let overallAverage = averages.reduce(0, +) / Double(averages.count)
        guard overallAverage > 0 else { return 100 }
        let maxDeviation = averages.map { abs($0 - overallAverage) }.max() ?? 0
        let deviationPercentage = (maxDeviation / overallAverage) * 100
        return max(0, 100 - deviationPercentage)
    }

    // MARK: - Level Completion Check

    private func checkLevelCompletion(level: Int) -> Bool {
        guard level >= 1, level <= LearningLevel.levels.count else { return false }
        let lvl = LearningLevel.levels[level - 1]
        let balance = calculateBalanceScore(level: level)

        let allPositions = lvl.allValidPositions
        let allReady = allPositions.allSatisfy { position in
            let key = position.trackingKey
            return (responseTimes[key]?.count ?? 0) >= 3
        }

        return allReady && balance >= lvl.targetBalance
    }

    // MARK: - Progress Tracking

    private func getAttemptsProgress() -> (completed: Int, total: Int) {
        let positions = currentLevel.allValidPositions
        let completed = positions.filter { position in
            let key = position.trackingKey
            return (responseTimes[key]?.count ?? 0) >= 3
        }.count
        return (completed, positions.count)
    }

    private func getLevelProgress() -> (progress: Double, balanceReady: Bool) {
        let positions = currentLevel.allValidPositions
        let balanceReady = positions.allSatisfy { position in
            let key = position.trackingKey
            return (responseTimes[key]?.count ?? 0) >= 3
        }

        if !balanceReady {
            return (0, false)
        }

        let progress = min(100, (balanceScore / currentLevel.targetBalance) * 100)
        return (progress, true)
    }

    private func getNotePositionData(level: Int) -> [PositionPerformance] {
        guard level >= 1, level <= LearningLevel.levels.count else { return [] }
        let lvl = LearningLevel.levels[level - 1]

        var data: [PositionPerformance] = []

        for (key, entry) in responseTimes {
            let parts = key.split(separator: "-")
            guard parts.count == 3,
                  let note = NoteName(rawValue: String(parts[0])),
                  let stringRaw = Int(parts[1]),
                  let string = BassString(rawValue: stringRaw),
                  let fret = Int(parts[2])
            else { continue }

            guard lvl.notes.contains(note), lvl.frets.contains(fret), !entry.times.isEmpty else { continue }

            data.append(PositionPerformance(
                string: string,
                fret: fret,
                note: note,
                average: entry.average,
                count: entry.times.count
            ))
        }

        data.sort { $0.sortKey < $1.sortKey }
        return data
    }

    // MARK: - Achievements

    private func checkAchievements(key: String, count: Int, note: NoteName, position: FretPosition) {
        // Position mastery (3+ correct)
        if count == 3 && !achievements.contains("\(key)-3x") {
            achievements.insert("\(key)-3x")
        }

        // Milestone achievements
        if gameStats.correct > 0 && gameStats.correct % 50 == 0 {
            let milestoneKey = "50-correct-\(gameStats.correct)"
            if !achievements.contains(milestoneKey) {
                achievements.insert(milestoneKey)
                triggerConfetti(.large)
                showAchievement("\(gameStats.correct) richtige Noten!")
            }
        }

        // Time-based achievements
        if let gameStart = gameStartTime {
            let elapsedMinutes = Int(Date().timeIntervalSince(gameStart) / 60)
            if elapsedMinutes > 0 && elapsedMinutes % 5 == 0 {
                let timeKey = "5-min-\(elapsedMinutes)"
                if !achievements.contains(timeKey) {
                    achievements.insert(timeKey)
                    triggerConfetti(.medium)
                    showAchievement("\(elapsedMinutes) Minuten! Weiter so!")
                }
            }
        }

        // Track recent notes for pattern detection
        let now = Date()
        recentNotes.append((note, now))
        recentNotes = recentNotes.filter { now.timeIntervalSince($0.timestamp) < 10 }

        // Triple A
        if recentNotes.count >= 3 {
            let lastThree = recentNotes.suffix(3).map(\.note)
            if lastThree.allSatisfy({ $0 == .a }) {
                triggerConfetti(.medium)
                showAchievement("Dreimal A!")
            }
        }

        // BACH pattern
        if recentNotes.count >= 4 {
            let lastFour = recentNotes.suffix(4).map(\.note)
            if lastFour == [.b, .a, .c] && !achievements.contains("bach") {
                // Note: H is not in our note system, using B-A-C-B as approximation
                achievements.insert("bach")
                triggerConfetti(.large)
                showAchievement("B-A-C-H!")
            }
        }

        // Speed demon: 3 correct in 2 seconds
        if recentNotes.count >= 3 {
            let lastThree = Array(recentNotes.suffix(3))
            if lastThree.last!.timestamp.timeIntervalSince(lastThree.first!.timestamp) < 2.0 {
                if !achievements.contains("speed-demon") {
                    achievements.insert("speed-demon")
                    triggerConfetti(.medium)
                    showAchievement("Tempo-Teufel!")
                }
            }
        }

        // Perfect fifth: C and G in sequence
        if recentNotes.count >= 2 {
            let lastTwo = recentNotes.suffix(2).map(\.note)
            if (lastTwo[0] == .c && lastTwo[1] == .g) || (lastTwo[0] == .g && lastTwo[1] == .c) {
                if !achievements.contains("perfect-fifth") {
                    achievements.insert("perfect-fifth")
                    triggerConfetti(.small)
                    showAchievement("Reine Quinte!")
                }
            }
        }

        // Chromatic run: 3 consecutive semitones
        if recentNotes.count >= 3 {
            let lastThreeNotes = recentNotes.suffix(3).map(\.note)
            let indices = lastThreeNotes.compactMap { NoteName.allNotes.firstIndex(of: $0) }
            if indices.count == 3 && indices[1] == indices[0] + 1 && indices[2] == indices[1] + 1 {
                if !achievements.contains("chromatic") {
                    achievements.insert("chromatic")
                    triggerConfetti(.medium)
                    showAchievement("Chromatik-Lauf!")
                }
            }
        }

        // Level progress milestones
        let positions = currentLevel.allValidPositions
        let positionsWithMinAttempts = responseTimes.values.filter { $0.count >= 3 }.count
        let progress = positions.isEmpty ? 0.0 : Double(positionsWithMinAttempts) / Double(positions.count)

        for milestone in [0.25, 0.5, 0.75] {
            let milestoneKey = "level-\(gameStats.level)-\(Int(milestone * 100))"
            if progress >= milestone && !achievements.contains(milestoneKey) {
                achievements.insert(milestoneKey)
                triggerConfetti(milestone >= 0.5 ? .medium : .small)
                showAchievement("\(Int(milestone * 100))% gemeistert")
            }
        }
    }

    // MARK: - Groove / Metronome

    private func startGroove() {
        guard metronomeTimer == nil else { return }
        let bpm = 80.0
        let interval = (60.0 / bpm) / 2.0 // 8th notes

        beatCounter = 0
        audioEngine.playGroove(beatNumber: beatCounter)
        beatCounter += 1

        metronomeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.audioEngine.playGroove(beatNumber: self.beatCounter)
                self.beatCounter += 1
            }
        }
    }

    private func stopGroove() {
        metronomeTimer?.invalidate()
        metronomeTimer = nil
        beatCounter = 0
    }

    // MARK: - Confetti & Achievements

    private func triggerConfetti(_ intensity: ConfettiIntensity) {
        confettiIntensity = intensity
        showConfetti = true
        audioEngine.playFireworks()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.showConfetti = false
        }
    }

    private func showAchievement(_ message: String) {
        achievementMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.achievementMessage == message {
                self?.achievementMessage = nil
            }
        }
    }

    // MARK: - Color Helpers

    func colorForTime(_ seconds: Double) -> Color {
        if seconds >= 10 { return Color(red: 0.8, green: 0.2, blue: 0.2) }
        if seconds >= 5 { return Color(red: 0.9, green: 0.5, blue: 0.2) }
        if seconds >= 2 { return Color(red: 0.9, green: 0.75, blue: 0.2) }
        if seconds >= 1 { return Color(red: 0.6, green: 0.8, blue: 0.2) }
        return Color(red: 0.2, green: 0.7, blue: 0.3)
    }
}
