import SwiftUI

/// Ziel eines Plan-Blocks – bestimmt, welche Übung direkt gestartet wird.
enum PlanTarget: Identifiable, Equatable {
    case warmup
    case orientation
    case pentatonic
    case pick
    case precision
    case technique(TechniqueExercise)
    case practiceClass(PracticeReason, contextOnly: Bool)
    case songs(SongSource, songID: String?)

    var id: String {
        switch self {
        case .warmup:      return "warmup"
        case .orientation: return "orientation"
        case .pentatonic:  return "pentatonic"
        case .pick:        return "pick"
        case .precision:   return "precision"
        case .technique(let ex): return "tech-\(ex.id)"
        case .practiceClass(let r, let ctx): return "pc-\(r.rawValue)-\(ctx ? "ctx" : "all")"
        case .songs(let s, let sid): return "songs-\(s == .setlist ? "set" : "rep")-\(sid ?? "any")"
        }
    }

    /// Label fürs Übungs-Log (identisch zu den Menü-Labels → konsistente Kategorien).
    var logLabel: String {
        switch self {
        case .warmup:      return "Warm-up"
        case .orientation: return "Orientierung"
        case .pentatonic:  return "Pentatonic Shapes"
        case .pick:        return "Pick"
        case .precision:   return "Oktaven"
        case .technique(let ex): return ex.logLabel
        case .practiceClass(let r, _): return r.label
        case .songs(let s, _): return s == .setlist ? "Aktuelle Setlist" : "Alle Songs"
        }
    }
}

/// Verfügbare Session-Längen.
enum SessionLength: Int, CaseIterable, Identifiable {
    case s15 = 15, s30 = 30, s45 = 45, s60 = 60
    var id: Int { rawValue }
    var label: String { "\(rawValue)" }
}

/// Ein Block der Tages-Session.
struct PlanBlock: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let minutes: Int
    let systemImage: String
    let target: PlanTarget
}

// MARK: - Planer

@MainActor
final class TodayPlanner: ObservableObject {
    @Published private(set) var blocks: [PlanBlock] = []
    @Published private(set) var isLoading = false

    var totalMinutes: Int { blocks.reduce(0) { $0 + $1.minutes } }

    private struct ProblemPick { let reason: PracticeReason; let count: Int; let days: Int? }

    func build(length: SessionLength) async {
        isLoading = true
        defer { isLoading = false }

        // Daten laden.
        let markerStore = PracticeMarkerStore()
        await markerStore.loadAll()

        let band = UserDefaults.standard.string(forKey: "selectedBandID")
        let setlist = SongCatalog(source: .setlist)
        await setlist.load(bandID: band)
        let setlistIDs = Set(setlist.songs.map { $0.id })

        let log = PracticeLogStore.shared
        if log.entries.isEmpty { await log.load() }

        let picks = rankedProblems(markers: markerStore.markers, setlistIDs: setlistIDs, log: log)

        // Tages-Rotation: jeden Tag andere Technik-/Pentatonik-Übungen.
        let seed = TechniqueLibrary.dayNumber
        let todaysTech = TechniqueLibrary.techniquesRotated(seed: seed)
        let todaysPenta = TechniqueLibrary.pentatonic(seed: seed)
        let setlistSongs = setlist.songs

        func warmup(_ m: Int) -> PlanBlock {
            PlanBlock(title: "Warm-up", subtitle: "Chromatic Crawl / Spider zum Klick",
                      minutes: m, systemImage: "flame.fill", target: .warmup)
        }
        func pentaBlock(_ m: Int) -> PlanBlock {
            PlanBlock(title: "Pentatonik · \(todaysPenta.name)", subtitle: todaysPenta.focus,
                      minutes: m, systemImage: todaysPenta.systemImage, target: .technique(todaysPenta))
        }
        // Problemstellen-Block Nr. i (oder Pentatonik-Fallback, wenn nicht genug Marker).
        func problem(_ i: Int, _ min: Int) -> PlanBlock {
            guard i < picks.count else { return pentaBlock(min) }
            let p = picks[i]
            let daysText = p.days.map { $0 == 0 ? "heute schon geübt" : "zuletzt vor \($0) Tg." } ?? "noch nie geübt"
            return PlanBlock(title: "Problemstellen · \(p.reason.label)",
                             subtitle: "\(p.count) markierte Stellen · \(daysText)",
                             minutes: min, systemImage: p.reason.systemImage, target: .practiceClass(p.reason, contextOnly: false))
        }
        // Geführte Technik-Übung (Vorspielen → Einzähler → Nachspielen + Bewertung).
        func tech(_ i: Int, _ m: Int) -> PlanBlock {
            guard !todaysTech.isEmpty else { return warmup(m) }
            let ex = todaysTech[i % todaysTech.count]
            return PlanBlock(title: "Technik · \(ex.name)", subtitle: ex.focus,
                             minutes: m, systemImage: ex.systemImage, target: .technique(ex))
        }
        // Play-along – immer dabei, mit täglich/rotierend wechselndem Setlist-Song.
        func play(_ m: Int, _ rot: Int) -> PlanBlock {
            let song = setlistSongs.isEmpty ? nil : setlistSongs[((seed + rot) % setlistSongs.count + setlistSongs.count) % setlistSongs.count]
            return PlanBlock(title: "Play-along", subtitle: song.map { "Setlist · \($0.name)" } ?? "Setlist – mitspielen",
                             minutes: m, systemImage: "music.note.list", target: .songs(.setlist, songID: song?.id))
        }

        switch length {
        case .s15:
            blocks = [warmup(2), tech(0, 4), problem(0, 4), play(6, 0)]
        case .s30:
            blocks = [warmup(3), tech(0, 5), tech(1, 4), problem(0, 6), pentaBlock(4), play(8, 0)]
        case .s45:
            blocks = [warmup(4), tech(0, 5), tech(1, 5), problem(0, 7), problem(1, 5), pentaBlock(6), play(13, 0)]
        case .s60:
            blocks = [warmup(5), tech(0, 6), tech(1, 5), tech(2, 5), problem(0, 8), problem(1, 6), pentaBlock(7), play(12, 0), play(6, 1)]
        }
    }

    /// Marker-Gründe nach Dringlichkeit: viele Stellen + lange nicht geübt +
    /// Bezug zur aktuellen Setlist.
    private func rankedProblems(markers: [PracticeMarker], setlistIDs: Set<String>, log: PracticeLogStore) -> [ProblemPick] {
        guard !markers.isEmpty else { return [] }
        let byReason = Dictionary(grouping: markers) { $0.reason }
        return byReason.map { reason, ms -> (ProblemPick, Double) in
            let count = ms.count
            let setlistHits = ms.filter { setlistIDs.contains($0.songID) }.count
            let days = daysSinceLastPracticed(label: reason.label, log: log)
            let recency = Double(days ?? 30)
            let score = Double(count) + recency * 0.5 + Double(setlistHits) * 2
            return (ProblemPick(reason: reason, count: count, days: days), score)
        }
        .sorted { $0.1 > $1.1 }
        .map { $0.0 }
    }

    private func daysSinceLastPracticed(label: String, log: PracticeLogStore) -> Int? {
        let dayStrings = log.entries.filter { $0.category == label }.map { $0.day }
        guard let latest = dayStrings.max() else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        guard let d = f.date(from: latest) else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day
    }
}

// MARK: - View

struct TodayView: View {
    @StateObject private var planner = TodayPlanner()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("todayLength") private var lengthRaw: Int = 30
    @State private var runningIndex: Int?
    @State private var done: Set<String> = []

    private var length: SessionLength { SessionLength(rawValue: lengthRaw) ?? .s30 }
    private var runningBlock: PlanBlock? {
        guard let i = runningIndex, planner.blocks.indices.contains(i) else { return nil }
        return planner.blocks[i]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Dauer", selection: $lengthRaw) {
                    ForEach(SessionLength.allCases) { Text("\($0.label) min").tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 8)
                Divider()
                content
            }
            .navigationTitle("Heute üben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Menü", systemImage: "chevron.left") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { done.removeAll(); Task { await planner.build(length: length) } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .task { if planner.blocks.isEmpty { await planner.build(length: length) } }
            .onChange(of: lengthRaw) { _, _ in done.removeAll(); Task { await planner.build(length: length) } }
            .fullScreenCover(item: Binding(get: { runningBlock }, set: { if $0 == nil { runningIndex = nil } })) { block in
                SessionBlockContainer(
                    title: block.title,
                    minutes: block.minutes,
                    onNext: {
                        done.insert(block.target.id)
                        if let i = runningIndex, i + 1 < planner.blocks.count { runningIndex = i + 1 }
                        else { runningIndex = nil }
                    },
                    onCancel: { runningIndex = nil }
                ) {
                    destination(for: block.target).logPractice(block.target.logLabel, active: true)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if planner.isLoading && planner.blocks.isEmpty {
            ProgressView("Stelle deine Session zusammen …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(Array(planner.blocks.enumerated()), id: \.element.id) { i, block in
                        Button { runningIndex = i } label: { row(block) }
                    }
                } header: {
                    let allDone = !planner.blocks.isEmpty && planner.blocks.allSatisfy { done.contains($0.target.id) }
                    Text(allDone ? "Session abgeschlossen 🎉" : "Heutige Session · \(planner.totalMinutes) min").textCase(nil)
                } footer: {
                    Text("Automatisch aus Best-Practice-Vorlage + deinen Markern, dem Übungs-Log und der Setlist. Tippe einen Block, um direkt zu starten – nach der Übung wird er automatisch abgehakt.")
                }
            }
        }
    }

    private func row(_ block: PlanBlock) -> some View {
        HStack(spacing: 12) {
            Image(systemName: block.systemImage)
                .font(.title3).foregroundColor(.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title).font(.headline)
                Text(block.subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text("\(block.minutes) min").font(.subheadline).monospacedDigit().foregroundColor(.secondary)
            let isDone = done.contains(block.target.id)
            Image(systemName: isDone ? "checkmark.circle.fill" : "play.circle.fill")
                .font(.title3).foregroundColor(isDone ? .green : .accentColor)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func destination(for target: PlanTarget) -> some View {
        switch target {
        case .warmup:      WarmupView()
        case .orientation: OrientationView()
        case .pentatonic:  PentatonicView()
        case .pick:        PickOctavesView()
        case .precision:   PrecisionOctavesView()
        case .technique(let ex): GuidedTechniqueView(exercise: ex)
        case .practiceClass(let r, let ctx): PracticeClassView(reason: r, contextOnly: ctx)
        case .songs(let s, let sid): SongsView(source: s, preselectID: sid)
        }
    }
}

// MARK: - Session-Block mit Timer + Dialog

/// Uhr für einen Block: läuft `seconds` herunter, danach eine kurze Nachspiel-
/// Karenz (damit der aktuelle Durchlauf zu Ende gespielt werden kann), dann
/// schaltet die Session automatisch weiter (`onAutoAdvance`).
@MainActor
final class BlockClock: ObservableObject {
    enum Phase { case running, grace }
    @Published var remaining = 0
    @Published var phase: Phase = .running
    @Published var graceLeft = 0
    var onAutoAdvance: (() -> Void)?

    private let graceSeconds = 10
    private var timer: Timer?

    func start(seconds: Int) {
        stop(); remaining = max(1, seconds); phase = .running; graceLeft = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickSecond() }
        }
    }

    private func tickSecond() {
        switch phase {
        case .running:
            if remaining > 0 { remaining -= 1 }
            if remaining <= 0 { phase = .grace; graceLeft = graceSeconds }
        case .grace:
            if graceLeft > 0 { graceLeft -= 1 }
            if graceLeft <= 0 { stop(); onAutoAdvance?() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }
}

/// Umschließt eine Übung, zeigt einen Countdown und nach Ablauf einen Dialog
/// „Nochmal / Weiter / Abbrechen".
struct SessionBlockContainer<Content: View>: View {
    let title: String
    let minutes: Int
    let onNext: () -> Void
    let onCancel: () -> Void
    let content: Content
    @StateObject private var clock = BlockClock()

    init(title: String, minutes: Int, onNext: @escaping () -> Void, onCancel: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.minutes = minutes
        self.onNext = onNext
        self.onCancel = onCancel
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
            VStack {
                HStack {
                    Spacer()
                    Text(clock.phase == .grace ? "Durchlauf zu Ende spielen …" : "\(clock.remaining / 60):\(String(format: "%02d", clock.remaining % 60))")
                        .font(.caption).monospacedDigit().fontWeight(.semibold)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.trailing, 12).padding(.top, 6)
                }
                Spacer()
            }
            if clock.phase == .grace { graceBanner }
        }
        .onAppear {
            clock.onAutoAdvance = onNext
            clock.start(seconds: minutes * 60)
        }
        .onDisappear { clock.stop() }
    }

    /// Nach Ablauf: dezenter Hinweis mit Auto-Weiter-Countdown; du kannst sofort
    /// weiter, den Block nochmal starten oder abbrechen.
    private var graceBanner: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Text("Zeit um · weiter in \(clock.graceLeft)s").font(.headline)
                Text("\(title) · \(minutes) min").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 12) {
                    Button("Nochmal") { clock.start(seconds: minutes * 60) }
                        .buttonStyle(.bordered)
                    Button("Jetzt weiter") { clock.stop(); onNext() }
                        .buttonStyle(.borderedProminent)
                    Button("Ende", role: .cancel) { clock.stop(); onCancel() }
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 18).fill(.regularMaterial))
            .padding(.horizontal, 24).padding(.bottom, 28)
        }
    }
}
