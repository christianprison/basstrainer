import SwiftUI

/// Prototype: live note detection from the (USB-)audio input.
/// No game logic yet — this validates the hardware path: plug in the
/// USB audio interface, play a note on the bass, see it recognised live.
struct TunerView: View {
    @StateObject private var tuner = TunerEngine()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            header

            Spacer()

            if tuner.permissionDenied {
                permissionDeniedView
            } else {
                noteDisplay
                centsMeter
                levelMeter
            }

            Spacer()

            controls
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onDisappear { tuner.stop() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pitch-Detection (Prototyp)")
                    .font(.headline)
                Text("Input: \(tuner.inputName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var noteDisplay: some View {
        VStack(spacing: 6) {
            Text(tuner.detected?.label ?? "—")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(noteColor)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.12), value: tuner.detected?.label)

            Text(tuner.detected.map { String(format: "%.1f Hz", $0.frequency) } ?? " ")
                .font(.title3)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
    }

    /// -50…+50 cents indicator. Green near center = in tune.
    private var centsMeter: some View {
        let cents = tuner.detected?.cents ?? 0
        return VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let clamped = max(-50, min(50, cents))
                let x = width / 2 + CGFloat(clamped / 50) * (width / 2)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 8)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 2, height: 20)
                        .position(x: width / 2, y: 4)
                    if tuner.detected != nil {
                        Circle()
                            .fill(noteColor)
                            .frame(width: 22, height: 22)
                            .position(x: x, y: 4)
                            .animation(.easeOut(duration: 0.12), value: cents)
                    }
                }
            }
            .frame(height: 24)

            Text(tuner.detected.map { String(format: "%+.0f cents", $0.cents) } ?? " ")
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var levelMeter: some View {
        VStack(spacing: 4) {
            ProgressView(value: Double(tuner.level), total: 1.0)
                .tint(.blue)
            Text("Eingangspegel")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var controls: some View {
        Button {
            tuner.isRunning ? tuner.stop() : tuner.start()
        } label: {
            Label(tuner.isRunning ? "Stopp" : "Start",
                  systemImage: tuner.isRunning ? "stop.fill" : "mic.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tuner.isRunning ? .red : .accentColor)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Mikrofon-Zugriff verweigert")
                .font(.headline)
            Text("Bitte in den Einstellungen unter Datenschutz → Mikrofon für Bass Trainer aktivieren.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private var noteColor: Color {
        guard let cents = tuner.detected?.cents else { return .primary }
        return abs(cents) < 8 ? .green : .primary
    }
}

#Preview {
    TunerView()
}
