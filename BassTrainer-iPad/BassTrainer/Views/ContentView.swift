import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
          VStack(spacing: 0) {
            topBar
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
          }

            // Großes, zentriertes Feedback (Korrektur deutlich sichtbar).
            if let feedback = viewModel.feedback {
                feedbackView(feedback)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }

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

        }
        .background(Color(.systemBackground))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.feedback)
    }

    // MARK: - Subviews

    /// Fest oben verankert: Menü + Timer sind so immer sichtbar (kein Scrollen).
    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Label("Menü", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            if viewModel.isPlaying && viewModel.feedback == nil {
                timerBar
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

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

    @ViewBuilder
    private func feedbackView(_ feedback: AnswerFeedback) -> some View {
        let correct = feedback == .correct
        // Helles, gut unterscheidbares Rot (farbenblind-freundlicher) bzw. Grün.
        // Zusätzlich zur Farbe unterschiedliche Form (Haken vs. Kreuz) → farbenblind-sicher.
        let color: Color = correct
            ? Color(red: 0.15, green: 0.72, blue: 0.40)
            : Color(red: 1.0, green: 0.32, blue: 0.30)
        VStack(spacing: 12) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 76, weight: .bold))
            if correct {
                Text("Richtig!")
                    .font(.system(size: 44, weight: .heavy))
            } else {
                Text("Falsch")
                    .font(.system(size: 34, weight: .heavy))
                Text("Richtig wäre")
                    .font(.title3)
                    .foregroundColor(.primary.opacity(0.7))
                Text(viewModel.currentNote.rawValue)
                    .font(.system(size: 104, weight: .black, design: .monospaced))
            }
        }
        .foregroundColor(color)
        .padding(.vertical, 32)
        .padding(.horizontal, 48)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(color, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .padding(40)
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
