import SwiftUI
import QuartzCore

/// Werkzeug „Timing kalibrieren": Metronom läuft auf 120 BPM, du spielst
/// Viertelnoten möglichst genau auf den Klick. Die App misst die systematische
/// Latenz (Median der Abweichungen) und speichert sie. Präzisionsübungen und
/// die Songanfang-Aufnahme rechnen den Wert danach heraus.
struct LatencyCalibrationView: View {
    @StateObject private var vm = LatencyCalibrationViewModel()
    @ObservedObject private var store = CalibrationStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            header
            switch vm.phase {
            case .intro:   introCard
            case .denied:  deniedCard
            case .countIn, .measuring: runningView
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear { Task { await store.loadIfNeeded() } }
        .onDisappear { vm.stop() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { vm.stop(); dismiss() } label: { Label("Menü", systemImage: "chevron.left") }
            VStack(alignment: .leading, spacing: 2) {
                Text("Timing kalibrieren").font(.title2).fontWeight(.bold)
                Text("Aktuelle Latenz: \(Int(store.latencyMs)) ms")
                    .font(.caption).foregroundColor(.secondary).monospacedDigit()
            }
            Spacer()
        }
    }

    private var introCard: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "metronome").font(.system(size: 40)).foregroundColor(.secondary)
            Text("Das Metronom läuft auf 120 BPM. Spiele nach dem Einzähler entspannt Viertelnoten genau auf jeden Klick. Die App misst, wie viel später dein Anschlag im Schnitt ankommt (Audio-/Interface-Latenz), und speichert diesen Wert.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
            Button { vm.start() } label: {
                Label("Mikrofon freigeben & starten", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            if store.latencyMs != 0 {
                Button("Kalibrierung zurücksetzen (0 ms)") { vm.resetToZero() }
                    .font(.caption).tint(.red)
            }
            if let s = vm.status { Text(s).font(.caption).foregroundColor(.secondary) }
            Spacer()
        }
    }

    private var deniedCard: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "mic.slash.fill").font(.system(size: 40)).foregroundColor(.secondary)
            Text("Kein Mikrofon-Zugriff. Bitte in Einstellungen → Datenschutz → Mikrofon für Bass Trainer aktivieren.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            Button("Zurück") { vm.reset() }.buttonStyle(.bordered)
            Spacer()
        }
    }

    private var runningView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("120").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                Text("BPM · \(vm.phase == .countIn ? "Einzähler …" : "spiele Viertel auf den Klick")")
                    .font(.caption).foregroundColor(.secondary)
                ProgressView(value: Double(vm.level), total: 1).tint(.accentColor).padding(.top, 4)
                Text("Input: \(vm.inputName)").font(.caption2).foregroundColor(.secondary)
            }
            .padding().frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            // Messergebnis
            VStack(spacing: 6) {
                if let med = vm.medianMs {
                    Text("\(med > 0 ? "+" : "")\(med) ms").font(.system(size: 34, weight: .bold)).monospacedDigit()
                    Text("gemessene Latenz (Median aus \(vm.samples.count) Anschlägen)")
                        .font(.caption).foregroundColor(.secondary)
                    if let sp = vm.spreadMs {
                        Text("Streuung ± \(sp) ms").font(.caption2).foregroundColor(.secondary).monospacedDigit()
                    }
                } else {
                    Text("Spiele auf den Beat …").foregroundColor(.secondary)
                }
                if let d = vm.lastDeltaMs {
                    Text("letzter Anschlag: \(d > 0 ? "+" : "")\(d) ms").font(.caption2).foregroundColor(.secondary).monospacedDigit()
                }
            }
            .padding().frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            if let s = vm.status { Text(s).font(.caption).foregroundColor(.green) }

            HStack(spacing: 12) {
                Button(role: .destructive) { vm.stop() } label: {
                    Label("Stoppen", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
                Button { vm.saveMeasured() } label: {
                    Label(vm.saving ? "Speichere …" : "Speichern", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(vm.saving || (vm.samples.count < 8))
            }
            if vm.samples.count < 8 {
                Text("Noch \(8 - vm.samples.count) Anschläge bis zum Speichern.")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class LatencyCalibrationViewModel: ObservableObject {
    enum Phase { case intro, countIn, measuring, denied }

    @Published var phase: Phase = .intro
    @Published var level: Float = 0
    @Published var inputName = "—"
    @Published var lastDeltaMs: Int?
    @Published var samples: [Double] = []   // Abweichungen in ms (Onset − Beat)
    @Published var saving = false
    @Published var status: String?

    let bpm = 120
    private let countInBeats = 4
    private let store = CalibrationStore.shared

    private let engine = ListeningEngine()
    private var scheduler: Timer?
    private var beats: [(id: Int, time: Double)] = []
    private var matched: Set<Int> = []
    private var beatCounter = 0
    private var nextBeatTime = 0.0
    private var measureStartTime = 0.0

    private var beatDur: Double { 60.0 / Double(bpm) }

    var medianMs: Int? {
        guard !samples.isEmpty else { return nil }
        let s = samples.sorted()
        let m = s.count / 2
        let v = s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
        return Int(v.rounded())
    }

    /// Mittlere absolute Abweichung vom Median (Streuungsmaß, robust).
    var spreadMs: Int? {
        guard let med = medianMs, samples.count > 1 else { return nil }
        let mad = samples.map { abs($0 - Double(med)) }.reduce(0, +) / Double(samples.count)
        return Int(mad.rounded())
    }

    func start() {
        Task { await store.loadIfNeeded() }
        engine.onLevel = { [weak self] v in Task { @MainActor in self?.level = v } }
        engine.onOnset = { [weak self] t, _ in Task { @MainActor in self?.onOnset(t) } }
        engine.start { [weak self] ok in
            guard let self else { return }
            if ok { self.begin() } else { self.phase = .denied }
        }
    }

    func stop() {
        scheduler?.invalidate(); scheduler = nil
        engine.stop()
        if phase != .denied { phase = .intro }
    }

    func reset() { phase = .intro }

    private func begin() {
        inputName = engine.inputName
        samples = []; matched = []; beats = []
        beatCounter = 0; lastDeltaMs = nil; status = nil
        phase = .countIn
        nextBeatTime = CACurrentMediaTime() + 0.5
        measureStartTime = nextBeatTime + Double(countInBeats) * beatDur
        scheduler = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        while nextBeatTime < now + 0.15 {
            let id = beatCounter
            beats.append((id, nextBeatTime))
            if beats.count > 32 { beats.removeFirst() }
            engine.scheduleTick(accent: id % 4 == 0, at: nextBeatTime)
            beatCounter += 1
            nextBeatTime += beatDur
        }
        if phase == .countIn, now >= measureStartTime { phase = .measuring }
    }

    private func onOnset(_ time: Double) {
        guard phase == .measuring, time >= measureStartTime - beatDur / 2 else { return }
        var bestId = -1, bestTime = 0.0, bestAbs = Double.infinity
        for b in beats where b.time >= measureStartTime - beatDur {
            let d = abs(time - b.time)
            if d < bestAbs { bestAbs = d; bestId = b.id; bestTime = b.time }
        }
        // Nur eindeutige Treffer innerhalb eines halben Beats zählen.
        guard bestId >= 0, !matched.contains(bestId), bestAbs < beatDur / 2 else { return }
        matched.insert(bestId)
        let delta = (time - bestTime) * 1000.0
        lastDeltaMs = Int(delta.rounded())
        samples.append(delta)
        if samples.count > 64 { samples.removeFirst() }
    }

    func saveMeasured() {
        guard let med = medianMs else { return }
        saving = true; status = nil
        Task {
            do { try await store.save(Double(med)); status = "Gespeichert: \(med) ms" }
            catch { status = "Fehler: \(error.localizedDescription)" }
            saving = false
        }
    }

    func resetToZero() {
        status = nil
        Task {
            do { try await store.save(0); status = "Zurückgesetzt (0 ms)" }
            catch { status = "Fehler: \(error.localizedDescription)" }
        }
    }
}

#Preview {
    LatencyCalibrationView()
}
