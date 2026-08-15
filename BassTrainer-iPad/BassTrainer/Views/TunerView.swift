import SwiftUI

/// Live-Tonhöhenerkennung vom (USB-)Audio-Eingang, dargestellt als scrollender
/// 5-Saiten-Tab-Zeitstrahl (Tonhöhen + Tondauern), mit variablem Metronom.
struct TunerView: View {
    @StateObject private var tuner = TunerEngine()
    @StateObject private var timeline = NoteTimelineModel()
    @StateObject private var metro = TunerMetronome()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            header
            if tuner.permissionDenied {
                Spacer(); permissionDeniedView; Spacer()
            } else {
                liveRow
                TabTimelineView(model: timeline, metro: metro)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                metronomeRow
                controls
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onChange(of: tuner.detected) { _, new in timeline.setDetected(new) }
        .onAppear {
            timeline.start()               // Zeitstrahl läuft durchgehend (Raster scrollt mit)
            if !metro.isRunning { metro.start() }   // Metronom per Default an
        }
        .onDisappear { stopAll() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tonhöhen-Erkennung").font(.headline)
                Text("Input: \(tuner.inputName)").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button { stopAll(); dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
            }
        }
    }

    /// Kompakte Live-Anzeige (Ton, Hz, Cents, Pegel) über dem Zeitstrahl.
    private var liveRow: some View {
        HStack(spacing: 16) {
            Text(tuner.detected?.label ?? "—")
                .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundColor(noteColor)
                .frame(minWidth: 90, alignment: .leading)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.1), value: tuner.detected?.label)
            VStack(alignment: .leading, spacing: 2) {
                Text(tuner.detected.map { String(format: "%.1f Hz", $0.frequency) } ?? " ")
                    .font(.caption).monospacedDigit().foregroundColor(.secondary)
                Text(tuner.detected.map { String(format: "%+.0f cents", $0.cents) } ?? " ")
                    .font(.caption).monospacedDigit().foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Pegel").font(.caption2).foregroundColor(.secondary)
                ProgressView(value: Double(tuner.level), total: 1.0).tint(.blue).frame(width: 120)
            }
        }
    }

    private var metronomeRow: some View {
        HStack(spacing: 12) {
            Button { metro.toggle() } label: {
                Image(systemName: metro.isRunning ? "metronome.fill" : "metronome")
                    .font(.title3)
                    .foregroundColor(metro.isRunning ? .accentColor : .primary)
            }
            Slider(value: $metro.bpm, in: 40...200, step: 1) { editing in if !editing { metro.bpmChanged() } }
            Text("\(Int(metro.bpm)) BPM").font(.caption).monospacedDigit().frame(width: 70)
        }
    }

    private var controls: some View {
        Button { toggleDetection() } label: {
            Label(tuner.isRunning ? "Stopp" : "Start",
                  systemImage: tuner.isRunning ? "stop.fill" : "mic.fill")
                .font(.headline).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .tint(tuner.isRunning ? .red : .accentColor)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash.fill").font(.system(size: 44)).foregroundColor(.secondary)
            Text("Mikrofon-Zugriff verweigert").font(.headline)
            Text("Bitte in den Einstellungen unter Datenschutz → Mikrofon für Bass Trainer aktivieren.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func toggleDetection() {
        if tuner.isRunning {
            tuner.stop()                 // Mikro aus; Zeitstrahl läuft für die Anzeige weiter
        } else {
            timeline.clear()             // frischer Verlauf
            timeline.start()             // (falls noch nicht) Display-Loop läuft
            tuner.start()
        }
    }

    private func stopAll() {
        tuner.stop(); timeline.stop(); metro.stop()
    }

    private var noteColor: Color {
        guard let cents = tuner.detected?.cents else { return .primary }
        return abs(cents) < 8 ? .green : .primary
    }
}

#Preview {
    TunerView()
}
