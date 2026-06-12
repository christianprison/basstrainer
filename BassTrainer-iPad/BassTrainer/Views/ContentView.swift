import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Main content
            ScrollView {
                VStack(spacing: 12) {
                    // Stats header with level, controls
                    StatsHeaderView(
                        gameStats: viewModel.gameStats,
                        currentLevel: viewModel.currentLevel,
                        isPlaying: viewModel.isPlaying,
                        onToggle: { viewModel.toggleGame() },
                        onReset: { viewModel.resetGame() }
                    )

                    // Progress section: Balance gauge + Response time chart
                    HStack(alignment: .top, spacing: 16) {
                        BalanceGaugeView(
                            score: viewModel.balanceScore,
                            target: viewModel.currentLevel.targetBalance,
                            attemptsProgress: viewModel.attemptsProgress,
                            balanceReady: viewModel.levelProgress.balanceReady
                        )

                        ResponseTimeChartView(
                            data: viewModel.notePositionData,
                            colorForTime: { viewModel.colorForTime($0) }
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )

                    // Level feedback banner
                    if let feedback = viewModel.levelFeedback {
                        Text(feedback)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor.opacity(0.15))
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Fretboard (real bass photo with perspective)
                    FretboardView(
                        currentPosition: viewModel.currentPosition,
                        isPlaying: viewModel.isPlaying,
                        levelColor: viewModel.currentLevel.color
                    )
                    .aspectRatio(4019.0 / 332.0, contentMode: .fit)

                    // Note input buttons
                    if viewModel.isPlaying && !viewModel.gameComplete {
                        NoteButtonsView(
                            notes: viewModel.currentLevel.notes,
                            isDisabled: viewModel.feedback != nil,
                            onNoteTapped: { note in
                                viewModel.submitAnswer(note)
                            }
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Timer bar when playing
                    if viewModel.isPlaying && viewModel.feedback == nil {
                        timerBar
                    }

                    // Feedback overlay
                    if let feedback = viewModel.feedback {
                        feedbackView(feedback)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Game complete
                    if viewModel.gameComplete {
                        gameCompleteView
                    }
                }
                .padding(16)
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.isPlaying)
            .animation(.easeInOut(duration: 0.3), value: viewModel.feedback)
            .animation(.easeInOut(duration: 0.3), value: viewModel.levelFeedback)

            // Confetti overlay
            if viewModel.showConfetti {
                ConfettiView(intensity: viewModel.confettiIntensity)
                    .ignoresSafeArea()
            }

            // Achievement banner
            if let message = viewModel.achievementMessage {
                VStack {
                    Spacer()
                    AchievementBannerView(message: message)
                        .padding(.bottom, 40)
                }
                .ignoresSafeArea()
            }

            // Back to main menu
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("Menü", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.top, 8)
                    .padding(.leading, 16)
                    Spacer()
                }
                Spacer()
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Subviews

    private var timerBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: viewModel.timeLeft, total: 8.0)
                .tint(timerColor)
                .animation(.linear(duration: 0.1), value: viewModel.timeLeft)

            Text(String(format: "%.1fs", viewModel.timeLeft))
                .font(.caption2)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
    }

    private var timerColor: Color {
        if viewModel.timeLeft > 5 { return .green }
        if viewModel.timeLeft > 2 { return .yellow }
        return .red
    }

    private func feedbackView(_ feedback: AnswerFeedback) -> some View {
        HStack(spacing: 8) {
            Image(systemName: feedback == .correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
            Text(feedback == .correct ? "Richtig!" : "Falsch – es war \(viewModel.currentNote.rawValue)")
                .font(.headline)
        }
        .foregroundColor(feedback == .correct ? .green : .red)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill((feedback == .correct ? Color.green : Color.red).opacity(0.1))
        )
    }

    private var gameCompleteView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)

            Text("Glückwunsch!")
                .font(.title)
                .fontWeight(.bold)

            Text("Du hast alle 8 Level gemeistert!")
                .font(.headline)
                .foregroundColor(.secondary)

            Button("Nochmal spielen") {
                viewModel.toggleGame()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

#Preview {
    ContentView()
}
