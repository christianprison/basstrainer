import SwiftUI

struct BalanceGaugeView: View {
    let score: Double
    let target: Double
    let attemptsProgress: (completed: Int, total: Int)
    let balanceReady: Bool

    var body: some View {
        if balanceReady {
            balanceGauge
        } else {
            attemptsProgressView
        }
    }

    // MARK: - Balance Gauge

    private var balanceGauge: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background arc
                ArcShape(startAngle: .degrees(135), endAngle: .degrees(405))
                    .stroke(Color(.systemGray5), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 120, height: 120)

                // Progress arc
                ArcShape(
                    startAngle: .degrees(135),
                    endAngle: .degrees(135 + (min(score, 100) / 100) * 270)
                )
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 120, height: 120)

                // Score text
                VStack(spacing: 2) {
                    Text("\(Int(score))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Balance")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Progress bar
            VStack(spacing: 4) {
                HStack {
                    Text("Balance")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(score))% / \(Int(target))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(score >= target ? .green : .primary)
                }

                ProgressView(value: min(score, 100), total: 100)
                    .tint(gaugeColor)
            }
        }
        .frame(width: 160)
    }

    // MARK: - Attempts Progress (before balance tracking starts)

    private var attemptsProgressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Fortschritt bis zur Balance-Messung")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(attemptsProgress.completed) / \(attemptsProgress.total)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }

            let progressValue = attemptsProgress.total > 0
                ? Double(attemptsProgress.completed) / Double(attemptsProgress.total)
                : 0

            ProgressView(value: progressValue)
                .tint(.accentColor)

            Text("Jede Position braucht 3+ richtige Antworten, bevor die Balance berechnet wird")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 240)
    }

    // MARK: - Helpers

    private var gaugeColor: Color {
        if score >= target { return .green }
        if score >= 50 { return .yellow }
        if score >= 30 { return .orange }
        return .red
    }
}

// MARK: - Arc Shape

struct ArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: min(rect.width, rect.height) / 2,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
        }
    }
}

#Preview {
    HStack(spacing: 40) {
        BalanceGaugeView(
            score: 72,
            target: 80,
            attemptsProgress: (15, 20),
            balanceReady: true
        )

        BalanceGaugeView(
            score: 0,
            target: 50,
            attemptsProgress: (8, 20),
            balanceReady: false
        )
    }
    .padding()
}
