import SwiftUI
import QuartzCore

/// Präzision → Oktaven: Spiele Oktaven genau auf den Metronom-Schlag. Das
/// Mikrofon misst dein Timing; sauberes Spiel erhöht das Tempo, ungenaues senkt es.
struct PrecisionOctavesView: View {
    @StateObject private var vm = PrecisionOctavesViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            header
            switch vm.phase {
            case .intro:   introCard
            case .denied:  deniedCard
            case .running: runningView
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onDisappear { vm.stop() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { vm.stop(); dismiss() } label: {
                Label("Menü", systemImage: "chevron.left")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Oktaven nach Metronom").font(.title2).fontWeight(.bold)
                Text("Präzision · Tempo passt sich automatisch an")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var introCard: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "mic.fill").font(.system(size: 40)).foregroundColor(.secondary)
            Text("Spiele Oktaven (z. B. E–E) genau auf jeden Metronom-Schlag. Das Mikrofon misst dein Timing; bei sauberem Spiel steigt das Tempo, bei Ungenauigkeit sinkt es.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Button { vm.start() } label: {
                Label("Mikrofon freigeben & starten", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
            // BPM + VU
            VStack(spacing: 6) {
                Text("\(vm.bpm)").font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                Text("BPM").font(.caption).foregroundColor(.secondary)
                ProgressView(value: Double(vm.level), total: 1).tint(.accentColor).padding(.top, 4)
                Text("Input: \(vm.inputName)").font(.caption2).foregroundColor(.secondary)
            }
            .padding().frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            // Letzter Treffer
            VStack(spacing: 6) {
                if let hit = vm.lastHit {
                    Text(hit.rating.label).font(.system(size: 28, weight: .bold)).foregroundColor(hit.rating.color)
                    Text("\(hit.delta > 0 ? "+" : "")\(hit.delta) ms \(hit.delta > 0 ? "(zu spät)" : hit.delta < 0 ? "(zu früh)" : "")")
                        .font(.caption).foregroundColor(.secondary).monospacedDigit()
                } else {
                    Text("Spiele auf den Beat …").foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(Array(vm.recentRatings.enumerated()), id: \.offset) { _, r in
                        Circle().fill(r.color).frame(width: 12, height: 12)
                    }
                }
                .frame(height: 14)
            }
            .padding().frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            // Statistik
            HStack {
                statCell("Genauigkeit", "\(vm.accuracy)%")
                statCell("Treffer", "\(vm.total)")
            }
            HStack(spacing: 8) {
                tag("Perfect", vm.stats[.perfect] ?? 0, .green)
                tag("Good", vm.stats[.good] ?? 0, Color(red: 0.5, green: 0.8, blue: 0.2))
                tag("Ok", vm.stats[.ok] ?? 0, .yellow)
                tag("Miss", vm.stats[.miss] ?? 0, .red)
            }

            Button(role: .destructive) { vm.stop() } label: {
                Label("Stoppen", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(title).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func tag(_ title: String, _ count: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.subheadline).fontWeight(.semibold).monospacedDigit()
            Text(title).font(.caption2)
        }
        .foregroundColor(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.12)))
    }
}

// MARK: - ViewModel

@MainActor
final class PrecisionOctavesViewModel: ObservableObject {
    enum Phase { case intro, running, denied }

    enum Rating: String {
        case perfect, good, ok, miss
        var label: String { rawValue.uppercased() }
        var color: Color {
            switch self {
            case .perfect: return .green
            case .good:    return Color(red: 0.5, green: 0.8, blue: 0.2)
            case .ok:      return .yellow
            case .miss:    return .red
            }
        }
    }
    struct HitRating { let delta: Int; let rating: Rating }

    @Published var phase: Phase = .intro
    @Published var bpm: Int = 70
    @Published var level: Float = 0
    @Published var lastHit: HitRating?
    @Published var recentRatings: [Rating] = []
    @Published var stats: [Rating: Int] = [.perfect: 0, .good: 0, .ok: 0, .miss: 0]
    @Published var inputName = "—"

    // Bewertungsfenster (ms) und Tempo-Grenzen
    private let perfectMs = 40.0, goodMs = 90.0, okMs = 160.0
    private let startBpm = 70, minBpm = 50, maxBpm = 160
    private let beatsPerEval = 8

    private let engine = ListeningEngine()
    private var scheduler: Timer?
    private var beats: [(id: Int, time: Double)] = []
    private var matched: Set<Int> = []
    private var beatCounter = 0
    private var nextBeatTime = 0.0
    private var evalWindow: [Rating] = []

    var total: Int { Rating.allRatings.reduce(0) { $0 + (stats[$1] ?? 0) } }
    var accuracy: Int {
        let t = total
        guard t > 0 else { return 0 }
        return Int((Double((stats[.perfect] ?? 0) + (stats[.good] ?? 0)) / Double(t)) * 100)
    }

    func start() {
        Task { await CalibrationStore.shared.loadIfNeeded() }
        engine.onLevel = { [weak self] v in Task { @MainActor in self?.level = v } }
        engine.onOnset = { [weak self] t, _ in Task { @MainActor in self?.evaluateOnset(t) } }
        engine.start { [weak self] granted in
            guard let self else { return }
            if granted { self.beginRunning() } else { self.phase = .denied }
        }
    }

    func stop() {
        scheduler?.invalidate(); scheduler = nil
        engine.stop()
        phase = .intro
    }

    func reset() { phase = .intro }

    // MARK: - Lauf

    private func beginRunning() {
        phase = .running
        inputName = engine.inputName
        bpm = startBpm
        stats = [.perfect: 0, .good: 0, .ok: 0, .miss: 0]
        recentRatings = []
        lastHit = nil
        beats = []
        matched = []
        beatCounter = 0
        evalWindow = []
        nextBeatTime = CACurrentMediaTime() + 0.4

        // Look-ahead-Scheduler: plant Beats und spielt sample-genaue Ticks.
        scheduler = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let lookahead = 0.15
        let beatDur = 60.0 / Double(bpm)
        let now = CACurrentMediaTime()
        while nextBeatTime < now + lookahead {
            let id = beatCounter
            beats.append((id, nextBeatTime))
            if beats.count > 32 { beats.removeFirst() }
            engine.scheduleTick(accent: id % 4 == 0, at: nextBeatTime)
            beatCounter += 1
            if beatCounter % beatsPerEval == 0 { maybeAdjustTempo() }
            nextBeatTime += beatDur
        }
    }

    private func evaluateOnset(_ rawTime: Double) {
        guard !beats.isEmpty else { return }
        // Kalibrierte Eingabe-Latenz herausrechnen (Onset kommt systematisch später).
        let time = rawTime - CalibrationStore.shared.latencySeconds
        var bestId = -1, bestTime = 0.0, bestAbs = Double.infinity
        for b in beats {
            let d = abs(time - b.time)
            if d < bestAbs { bestAbs = d; bestId = b.id; bestTime = b.time }
        }
        guard bestId >= 0, !matched.contains(bestId) else { return }
        matched.insert(bestId)

        let delta = (time - bestTime) * 1000.0
        let absMs = abs(delta)
        let rating: Rating = absMs <= perfectMs ? .perfect : absMs <= goodMs ? .good : absMs <= okMs ? .ok : .miss

        lastHit = HitRating(delta: Int(delta.rounded()), rating: rating)
        stats[rating, default: 0] += 1
        recentRatings = (Array([rating] + recentRatings)).prefix(8).map { $0 }
        evalWindow.append(rating)
    }

    private func maybeAdjustTempo() {
        guard evalWindow.count >= beatsPerEval else { return }
        let score = evalWindow.reduce(0.0) { acc, r in
            acc + (r == .perfect ? 1 : r == .good ? 0.7 : r == .ok ? 0.3 : 0)
        } / Double(evalWindow.count)
        evalWindow = []
        if score >= 0.8 { bpm = min(maxBpm, bpm + 6) }
        else if score < 0.4 { bpm = max(minBpm, bpm - 6) }
    }
}

private extension PrecisionOctavesViewModel.Rating {
    static var allRatings: [PrecisionOctavesViewModel.Rating] { [.perfect, .good, .ok, .miss] }
}

#Preview {
    PrecisionOctavesView()
}
