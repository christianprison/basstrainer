import SwiftUI

struct ResponseTimeChartView: View {
    let data: [PositionPerformance]
    let colorForTime: (Double) -> Color

    private let maxDisplayTime: Double = 10.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Antwortzeiten nach Position (Saite & Bund)")
                .font(.caption)
                .fontWeight(.semibold)

            if data.isEmpty {
                Text("Spiele, um Antwortzeiten zu sehen")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .multilineTextAlignment(.center)
            } else {
                // Bar chart
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(data) { position in
                            barColumn(for: position)
                        }
                    }
                    .frame(height: 130)
                    .padding(.horizontal, 4)
                }

                // Legend
                legend
            }
        }
    }

    // MARK: - Bar Column

    private func barColumn(for position: PositionPerformance) -> some View {
        let avgSeconds = position.average
        let barHeight = min(1.0, avgSeconds / maxDisplayTime)
        let barColor = colorForTime(avgSeconds)

        return VStack(spacing: 2) {
            // Count label
            Text("\(position.count)x")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)

            // Bar
            VStack {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(height: max(2, CGFloat(barHeight) * 90))
            }
            .frame(height: 90)

            // Note label
            Text(position.note.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)

            // String/Fret label
            Text("\(BassString(rawValue: position.string.rawValue)?.name ?? "")\(position.fret)")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 24)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack {
            Text("Gruppiert nach Bund, dann nach Saite (B-E-A-D-G)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Spacer()

            HStack(spacing: 8) {
                legendItem(color: colorForTime(0.5), label: "<1s")
                legendItem(color: colorForTime(1.5), label: "1-2s")
                legendItem(color: colorForTime(3.0), label: "2-5s")
                legendItem(color: colorForTime(7.0), label: "5-10s")
                legendItem(color: colorForTime(10.0), label: ">10s")
            }
        }
        .padding(.top, 4)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ResponseTimeChartView(
        data: [
            PositionPerformance(string: .b, fret: 3, note: .d, average: 1.2, count: 5),
            PositionPerformance(string: .e, fret: 3, note: .g, average: 2.5, count: 3),
            PositionPerformance(string: .a, fret: 5, note: .d, average: 0.8, count: 7),
            PositionPerformance(string: .d, fret: 7, note: .a, average: 4.2, count: 2),
            PositionPerformance(string: .g, fret: 5, note: .c, average: 6.5, count: 4),
        ],
        colorForTime: { seconds in
            if seconds >= 10 { return .red }
            if seconds >= 5 { return .orange }
            if seconds >= 2 { return .yellow }
            if seconds >= 1 { return Color(red: 0.6, green: 0.8, blue: 0.2) }
            return .green
        }
    )
    .padding()
}
