import SwiftUI
import QuartzCore

/// Übung „Songanfänge merken": zufälliger Song mit hinterlegtem Anfang →
/// 2-Takt-Einzähler → Anfang aus dem Gedächtnis spielen → Mikro bewertet
/// Tonhöhe (oktav-tolerant) und Rhythmus.
struct IntroQuizView: View {
    @StateObject private var vm = IntroQuizViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Songanfänge merken")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { vm.stopAll(); dismiss() } label: { Label("Menü", systemImage: "chevron.left") }
                    }
                }
        }
        .task { await vm.load() }
        .onDisappear { vm.stopAll() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .loading:   ProgressView("Lade Songanfänge …").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:     emptyView
        case .ready:     readyView
        case .countIn:   playView(countingIn: true)
        case .listening: playView(countingIn: false)
        case .result:    resultView
        case .denied:    deniedView
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list").font(.system(size: 40)).foregroundColor(.secondary)
            Text("Noch keine Songanfänge hinterlegt.").font(.headline)
            Text("Nimm welche über Werkzeuge → „Intro einspielen“ auf.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            if let e = vm.error { Text(e).font(.caption2).foregroundColor(.red) }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyView: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 6) {
                Text("Welcher Anfang?").font(.caption).foregroundColor(.secondary)
                Text(vm.song?.name ?? "—").font(.largeTitle).fontWeight(.bold).multilineTextAlignment(.center)
                if let artist = vm.song?.artist { Text(artist).font(.headline).foregroundColor(.secondary) }
                if let bpm = vm.song?.bpm { Text("\(bpm) BPM").font(.caption).foregroundColor(.secondary) }
            }
            Text("Spiele den Anfang aus dem Gedächtnis.").font(.subheadline).foregroundColor(.secondary)
            Button { vm.start() } label: {
                Label("Start – 2 Takte Einzähler", systemImage: "play.fill").font(.headline)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Anderer Song") { vm.pickRandom() }.font(.caption)
            Spacer()
        }
        .padding()
    }

    private func playView(countingIn: Bool) -> some View {
        VStack(spacing: 20) {
            Text(vm.song?.name ?? "—").font(.title2).bold()
            Text(countingIn ? "Einzähler … (\(vm.countInBeats) Schläge)" : "Jetzt spielen!")
                .font(.title3).foregroundColor(countingIn ? .secondary : .accentColor)
            ProgressView(value: Double(vm.level), total: 1).tint(.accentColor).padding(.horizontal, 40)
            Text("\(vm.playedCount) Töne erkannt").font(.caption).foregroundColor(.secondary)
            if !countingIn {
                Button { vm.finish() } label: {
                    Label("Fertig", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal, 40)
            }
            Spacer()
        }
        .padding()
    }

    private var resultView: some View {
        VStack(spacing: 16) {
            Text(vm.song?.name ?? "—").font(.title2).bold()
            if let r = vm.result {
                Text("\(r.correct) / \(r.total) Tönen richtig")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(r.correct == r.total ? .green : (r.correct == 0 ? .red : .orange))
                if r.correct > 0 {
                    Text("Rhythmus: ø \(r.rhythmMs) ms Abweichung").font(.caption).foregroundColor(.secondary)
                }
                // erwartete Töne mit Treffer-Markierung
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(r.expected.enumerated()), id: \.offset) { i, note in
                            VStack(spacing: 2) {
                                Image(systemName: r.matched[i] ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundColor(r.matched[i] ? .green : .red)
                                Text(BassIntro.noteName(forMidi: note.midi)).font(.caption2).monospacedDigit()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("So geht der Anfang:").font(.caption).foregroundColor(.secondary)
                    BassTabView(notes: r.expected)
                }
                .padding(.horizontal)
            }
            HStack {
                Button { vm.start() } label: { Label("Nochmal", systemImage: "arrow.clockwise") }
                Spacer()
                Button { vm.pickRandom() } label: { Label("Nächster Song", systemImage: "forward.fill") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 30)
            Spacer()
        }
        .padding(.top)
    }

    private var deniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash.fill").font(.system(size: 40)).foregroundColor(.secondary)
            Text("Kein Mikrofon-Zugriff. Bitte in Einstellungen → Datenschutz → Mikrofon aktivieren.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).padding()
            Button("Zurück") { vm.phase = .ready }.buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - ViewModel

@MainActor
final class IntroQuizViewModel: ObservableObject {
    enum Phase { case loading, empty, ready, countIn, listening, result, denied }

    struct QuizResult {
        let correct: Int
        let total: Int
        let rhythmMs: Int
        let expected: [IntroNote]
        let matched: [Bool]
    }

    @Published var phase: Phase = .loading
    @Published var song: CatalogSong?
    @Published var level: Float = 0
    @Published var playedCount = 0
    @Published var result: QuizResult?
    @Published var error: String?

    let countInBeats = 8   // 2 Takte 4/4

    private let catalog = SongCatalog(source: .repertoire)
    private let repo = IntroRepository()
    private let recorder = IntroRecorder()

    private var pool: [CatalogSong] = []
    private var expected: [IntroNote] = []
    private var played: [(time: Double, midi: Int)] = []

    private var scheduler: Timer?
    private var endTimer: Timer?
    private var beatCounter = 0
    private var nextBeatTime: Double = 0
    private var downbeatTime: Double = 0
    private var listening = false

    private var bpm: Int { max(40, song?.bpm ?? 100) }
    private var beatDur: Double { 60.0 / Double(bpm) }

    func load() async {
        guard pool.isEmpty else { return }
        phase = .loading
        await catalog.load()
        do {
            let ids = Set(try await repo.songIDsWithIntro())
            pool = catalog.songs.filter { ids.contains($0.id) }
            if pool.isEmpty { phase = .empty } else { pickRandom() }
        } catch {
            self.error = error.localizedDescription
            phase = .empty
        }
    }

    func pickRandom() {
        guard let s = pool.randomElement() else { phase = .empty; return }
        song = s
        result = nil
        played = []
        playedCount = 0
        Task {
            expected = (try? await repo.load(songID: s.id)) ?? []
            phase = .ready
        }
    }

    func start() {
        played = []
        playedCount = 0
        result = nil
        recorder.sensitivity = 0.6
        recorder.onLevel = { [weak self] v in Task { @MainActor in self?.level = v } }
        recorder.onNote = { [weak self] t, midi, _ in Task { @MainActor in self?.gotNote(time: t, midi: midi) } }
        recorder.start { [weak self] granted in
            guard let self else { return }
            if granted { self.beginCountIn() } else { self.phase = .denied }
        }
    }

    private func beginCountIn() {
        phase = .countIn
        listening = false
        beatCounter = 0
        nextBeatTime = CACurrentMediaTime() + 0.5
        downbeatTime = nextBeatTime + Double(countInBeats) * beatDur
        scheduler = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Auto-Ende nach dem letzten erwarteten Ton + 2 Schläge.
        let lastBeat = expected.map { $0.beat }.max() ?? 4
        let endDelay = 0.5 + (Double(countInBeats) + lastBeat + 2) * beatDur
        endTimer = Timer.scheduledTimer(withTimeInterval: endDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        while nextBeatTime < now + 0.15 {
            recorder.scheduleTick(accent: beatCounter % 4 == 0, at: nextBeatTime)
            beatCounter += 1
            nextBeatTime += beatDur
        }
        if !listening && now >= downbeatTime {
            listening = true
            phase = .listening
        }
    }

    private func gotNote(time: Double, midi: Int) {
        guard listening, time >= downbeatTime - 0.05 else { return }
        played.append((time, midi))
        playedCount = played.count
    }

    func finish() {
        scheduler?.invalidate(); scheduler = nil
        endTimer?.invalidate(); endTimer = nil
        recorder.stop()
        level = 0
        evaluate()
        phase = .result
    }

    private func evaluate() {
        var matched = [Bool](repeating: false, count: expected.count)
        var used = [Bool](repeating: false, count: played.count)
        var deltas: [Double] = []
        let window = 0.6 * beatDur     // Zeitfenster für einen Treffer

        for (i, e) in expected.enumerated() {
            let expTime = downbeatTime + e.beat * beatDur
            var bestJ = -1
            var bestAbs = Double.infinity
            for (j, p) in played.enumerated() where !used[j] {
                guard pitchMatches(expected: e.midi, played: p.midi) else { continue }
                let d = abs(p.time - expTime)
                if d <= window && d < bestAbs { bestAbs = d; bestJ = j }
            }
            if bestJ >= 0 {
                matched[i] = true
                used[bestJ] = true
                deltas.append((played[bestJ].time - expTime) * 1000)
            }
        }
        let correct = matched.filter { $0 }.count
        let rhythm = deltas.isEmpty ? 0 : Int(deltas.map { abs($0) }.reduce(0, +) / Double(deltas.count))
        result = QuizResult(correct: correct, total: expected.count, rhythmMs: rhythm, expected: expected, matched: matched)
    }

    /// Oktav-toleranter Vergleich: gleicher Tonname zählt als richtig.
    private func pitchMatches(expected: Int, played: Int) -> Bool {
        (((expected - played) % 12) + 12) % 12 == 0
    }

    func stopAll() {
        scheduler?.invalidate(); scheduler = nil
        endTimer?.invalidate(); endTimer = nil
        recorder.stop()
        listening = false
        level = 0
    }
}
