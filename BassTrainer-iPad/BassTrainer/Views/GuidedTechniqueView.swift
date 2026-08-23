import SwiftUI
import QuartzCore

/// Geführte Technik-Übung: erst spielt die App die Übung einmal vor, dann ein
/// Einzähler, dann spielst du sie nach. Dabei „hört" die App zu und bewertet
/// Tonhöhe und Timing (mit kalibrierter Latenz). Läuft in Schleife, bis der
/// Session-Timer weiterschaltet.
struct GuidedTechniqueView: View {
    @StateObject private var vm: GuidedTechniqueViewModel
    @Environment(\.dismiss) private var dismiss

    init(exercise: TechniqueExercise) {
        _vm = StateObject(wrappedValue: GuidedTechniqueViewModel(exercise: exercise))
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            phaseBanner
            board
            if vm.phase == .play { scoreRow }
            transportHint
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { vm.stop(); dismiss() } label: { Label("Menü", systemImage: "chevron.left") }
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.exercise.name).font(.headline)
                Text(vm.exercise.focus).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text("\(vm.exercise.bpm) BPM").font(.caption).monospacedDigit().foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var phaseBanner: some View {
        switch vm.phase {
        case .demo:
            label("Hör zu – die Übung wird vorgespielt", "speaker.wave.2.fill", .accentColor)
        case .countIn:
            label("Einzähler … gleich mitspielen", "metronome.fill", .orange)
        case .play:
            Text(vm.exercise.howTo).font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
        case .denied:
            label("Kein Mikrofon-Zugriff (Einstellungen → Datenschutz → Mikrofon)", "mic.slash.fill", .red)
        }
    }

    private func label(_ text: String, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon).font(.subheadline).foregroundColor(color)
            .multilineTextAlignment(.center)
    }

    private var board: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            let w: CGFloat = 1800
            FretboardView(
                currentPosition: nil, isPlaying: false, levelColor: .accentColor,
                markers: vm.exercise.positions,
                markerColor: Color(red: 0.20, green: 0.50, blue: 0.95),
                rootMarkers: vm.currentPosition.map { [$0] } ?? [],
                rootColor: Color(red: 0.90, green: 0.20, blue: 0.55),
                markerScale: 0.78
            )
            .frame(width: w, height: w * 332.0 / 4019.0)
        }
    }

    private var scoreRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                stat("Tonhöhe", "\(vm.pitchAccuracy)%", vm.pitchAccuracy >= 80 ? .green : .orange)
                stat("Timing", "\(vm.timingAccuracy)%", vm.timingAccuracy >= 80 ? .green : .orange)
                stat("Töne", "\(vm.pitchTotal)", .secondary)
            }
            HStack(spacing: 12) {
                if let ok = vm.lastPitchOK {
                    Label(ok ? "Ton richtig" : "Ton daneben", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(ok ? .green : .red).font(.caption)
                }
                if let ms = vm.lastTimingMs {
                    Text("\(ms > 0 ? "+" : "")\(ms) ms").font(.caption).monospacedDigit().foregroundColor(.secondary)
                }
            }
            ProgressView(value: Double(vm.level), total: 1).tint(.accentColor)
        }
        .padding(.horizontal, 24)
    }

    private var transportHint: some View {
        Text(vm.phase == .play ? "Spiele die Töne mit dem Klick – die App bewertet mit."
             : (vm.phase == .demo ? "Danach zählt die App ein und du spielst nach." : " "))
            .font(.caption2).foregroundColor(.secondary)
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit().foregroundColor(color)
            Text(title).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - ViewModel

@MainActor
final class GuidedTechniqueViewModel: ObservableObject {
    enum Phase { case demo, countIn, play, denied }

    @Published var phase: Phase = .demo
    @Published var level: Float = 0
    @Published var demoIndex = 0
    @Published var expectedIndex = 0
    @Published var lastPitchOK: Bool?
    @Published var lastTimingMs: Int?
    @Published var pitchHits = 0
    @Published var pitchTotal = 0
    @Published var timingHits = 0

    let exercise: TechniqueExercise
    private let audio = AudioEngine()
    private let recorder = IntroRecorder()

    private var demoTimer: Timer?
    private var scheduler: Timer?
    private var beats: [(id: Int, time: Double, pc: Int)] = []
    private var matched: Set<Int> = []
    private var nextBeatTime = 0.0
    private var downbeatTime = 0.0
    private let countInBeats = 4

    private var beatDur: Double { 60.0 / Double(max(30, exercise.bpm)) }

    var pitchAccuracy: Int { pitchTotal > 0 ? Int((Double(pitchHits) / Double(pitchTotal) * 100).rounded()) : 0 }
    var timingAccuracy: Int { pitchTotal > 0 ? Int((Double(timingHits) / Double(pitchTotal) * 100).rounded()) : 0 }

    var currentPosition: FretPosition? {
        let p = exercise.positions
        guard !p.isEmpty else { return nil }
        switch phase {
        case .demo: return p[demoIndex % p.count]
        case .play: return p[expectedIndex % p.count]
        default:    return nil
        }
    }

    init(exercise: TechniqueExercise) { self.exercise = exercise }

    func start() {
        Task { await CalibrationStore.shared.loadIfNeeded() }
        startDemo()
    }

    func stop() {
        demoTimer?.invalidate(); demoTimer = nil
        scheduler?.invalidate(); scheduler = nil
        recorder.stop()
        level = 0
    }

    // MARK: Vorspielen

    private func startDemo() {
        phase = .demo; demoIndex = 0
        guard let first = exercise.positions.first else { beginListening(); return }
        audio.playBassNote(position: first)
        demoTimer = Timer.scheduledTimer(withTimeInterval: beatDur, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.demoStep() }
        }
    }

    private func demoStep() {
        let p = exercise.positions
        demoIndex += 1
        if demoIndex >= p.count {
            demoTimer?.invalidate(); demoTimer = nil
            beginListening()
            return
        }
        audio.playBassNote(position: p[demoIndex])
    }

    // MARK: Einzähler + Nachspielen

    private func beginListening() {
        recorder.onLevel = { [weak self] v in Task { @MainActor in self?.level = v } }
        recorder.onNote = { [weak self] t, midi, _ in Task { @MainActor in self?.onNote(t, midi) } }
        recorder.start { [weak self] ok in
            guard let self else { return }
            if ok { self.beginCountIn() } else { self.phase = .denied }
        }
    }

    private func beginCountIn() {
        phase = .countIn
        beats = []; matched = []
        pitchHits = 0; pitchTotal = 0; timingHits = 0
        lastPitchOK = nil; lastTimingMs = nil; expectedIndex = 0
        nextBeatTime = CACurrentMediaTime() + 0.5
        downbeatTime = nextBeatTime + Double(countInBeats) * beatDur
        scheduler = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func expectedPC(_ j: Int) -> Int {
        let p = exercise.positions
        guard !p.isEmpty else { return -1 }
        let note = p[((j % p.count) + p.count) % p.count].note
        return NoteName.allCases.firstIndex(of: note) ?? -1
    }

    private func tick() {
        let now = CACurrentMediaTime()
        while nextBeatTime < now + 0.15 {
            if nextBeatTime < downbeatTime - 0.001 {
                recorder.scheduleTick(accent: true, at: nextBeatTime)   // Einzähler
            } else {
                let j = Int(((nextBeatTime - downbeatTime) / beatDur).rounded())
                beats.append((id: j, time: nextBeatTime, pc: expectedPC(j)))
                if beats.count > 64 { beats.removeFirst() }
                recorder.scheduleTick(accent: j % max(1, exercise.positions.count) == 0, at: nextBeatTime)
            }
            nextBeatTime += beatDur
        }
        if phase == .countIn, now >= downbeatTime { phase = .play }
        if phase == .play {
            let count = max(1, exercise.positions.count)
            expectedIndex = max(0, Int((now - downbeatTime) / beatDur)) % count
        }
    }

    private func onNote(_ time: Double, _ midi: Int) {
        guard phase == .play, !beats.isEmpty else { return }
        let t = time - CalibrationStore.shared.latencySeconds
        var bestId = -1, bestTime = 0.0, bestPC = -1, bestAbs = Double.infinity
        for b in beats {
            let d = abs(t - b.time)
            if d < bestAbs { bestAbs = d; bestId = b.id; bestTime = b.time; bestPC = b.pc }
        }
        guard bestId >= 0, !matched.contains(bestId), bestAbs < beatDur / 2 else { return }
        matched.insert(bestId)

        let deltaMs = (t - bestTime) * 1000.0
        let pc = ((midi % 12) + 12) % 12
        let pitchOK = (pc == bestPC)
        pitchTotal += 1
        if pitchOK { pitchHits += 1 }
        if abs(deltaMs) <= 90 { timingHits += 1 }
        lastPitchOK = pitchOK
        lastTimingMs = Int(deltaMs.rounded())
    }
}

#Preview {
    GuidedTechniqueView(exercise: TechniqueLibrary.techniques[0])
}
