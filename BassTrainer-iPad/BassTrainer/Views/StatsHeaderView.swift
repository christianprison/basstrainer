import SwiftUI

struct StatsHeaderView: View {
    let gameStats: GameStats
    let currentLevel: LearningLevel
    let isPlaying: Bool
    let onToggle: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                // Level indicators
                levelIndicators

                Spacer()

                // Stats
                statsRow

                Spacer()

                // Control buttons
                controlButtons
            }

            // Level description
            VStack(spacing: 2) {
                Text(currentLevel.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(currentLevel.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Subviews

    private var levelIndicators: some View {
        HStack(spacing: 6) {
            Text("Level:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            ForEach(1...8, id: \.self) { level in
                ZStack {
                    Circle()
                        .fill(levelCircleColor(for: level))
                        .frame(width: 28, height: 28)

                    if level == gameStats.level {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 32, height: 32)
                    }

                    Text("\(level)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(levelTextColor(for: level))
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            StatItem(label: "Correct", value: "\(gameStats.correct)", color: .green)
            StatItem(label: "Wrong", value: "\(gameStats.incorrect)", color: .red)
            StatItem(label: "Streak", value: "\(gameStats.streak)", color: .accentColor)
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
                Text("\(gameStats.bestStreak)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.yellow)
            }
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Label(
                    isPlaying ? "Pause" : "Start",
                    systemImage: isPlaying ? "pause.fill" : "play.fill"
                )
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPlaying ? Color(.systemGray5) : Color.accentColor)
                )
                .foregroundColor(isPlaying ? .primary : .white)
            }
            .buttonStyle(.plain)

            Button(action: onReset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
        }
    }

    // MARK: - Helpers

    private func levelCircleColor(for level: Int) -> Color {
        if level == gameStats.level {
            return Color.accentColor
        } else if level < gameStats.level {
            return Color.green.opacity(0.3)
        } else {
            return Color(.systemGray5)
        }
    }

    private func levelTextColor(for level: Int) -> Color {
        if level == gameStats.level {
            return .white
        } else if level < gameStats.level {
            return .green
        } else {
            return .secondary
        }
    }
}

// MARK: - Stat Item

private struct StatItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
    }
}

#Preview {
    StatsHeaderView(
        gameStats: GameStats(correct: 42, incorrect: 3, streak: 5, bestStreak: 12),
        currentLevel: LearningLevel.levels[0],
        isPlaying: true,
        onToggle: {},
        onReset: {}
    )
    .padding()
}
