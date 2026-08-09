import SwiftUI

/// Ziel eines Plan-Blocks – bestimmt, welche Übung direkt gestartet wird.
enum PlanTarget: Identifiable, Equatable {
    case warmup
    case orientation
    case pentatonic
    case pick
    case precision
    case practiceClass(PracticeReason, contextOnly: Bool)
    case songs(SongSource)

    var id: String {
        switch self {
        case .warmup:      return "warmup"
        case .orientation: return "orientation"
        case .pentatonic:  return "pentatonic"
        case .pick:        return "pick"
        case .precision:   return "precision"
        case .practiceClass(let r, let ctx): return "pc-\(r.rawValue)-\(ctx ? "ctx" : "all")"
        case .songs(let s): return "songs-\(s == .setlist ? "set" : "rep")"
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
        case .practiceClass(let r, _): return r.label
        case .songs(let s): return s == .setlist ? "Aktuelle Setlist" : "Alle Songs"
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
        // Nur „im Zusammenhang"-Marker (für kurze Sessions als Playalong-Ersatz).
        let contextPicks = rankedProblems(markers: markerStore.markers.filter { $0.mode == .context },
                                          setlistIDs: setlistIDs, log: log)
        let isPick = Calendar.current.component(.weekday, from: Date()) % 2 == 0

        // Problemstellen-Block Nr. i (oder Skalen-Fallback, wenn nicht genug Marker).
        func problem(_ i: Int, _ min: Int) -> PlanBlock {
            guard i < picks.count else {
                return PlanBlock(title: "Skalen & Griffbrett",
                                 subtitle: "Pentatonik/Orientierung – frei über den Hals",
                                 minutes: min, systemImage: "square.grid.3x3.fill", target: .pentatonic)
            }
            let p = picks[i]
            let daysText = p.days.map { $0 == 0 ? "heute schon geübt" : "zuletzt vor \($0) Tg." } ?? "noch nie geübt"
            return PlanBlock(title: "Problemstellen · \(p.reason.label)",
                             subtitle: "\(p.count) markierte Stellen · \(daysText)",
                             minutes: min, systemImage: p.reason.systemImage, target: .practiceClass(p.reason, contextOnly: false))
        }
        func warmup(_ m: Int) -> PlanBlock {
            PlanBlock(title: "Warm-up", subtitle: "Chromatic Crawl / Spider zum Klick",
                      minutes: m, systemImage: "flame.fill", target: .warmup)
        }
        func fretboard(_ m: Int) -> PlanBlock {
            PlanBlock(title: "Griffbrett", subtitle: "Pentatonic Shapes – eine Lage",
                      minutes: m, systemImage: "square.grid.3x3.fill", target: .pentatonic)
        }
        func technique(_ m: Int) -> PlanBlock {
            PlanBlock(title: isPick ? "Technik · Pick-Oktaven" : "Technik · Präzision",
                      subtitle: "Oktaven zum Klick, progressiv schneller",
                      minutes: m, systemImage: "bolt.fill", target: isPick ? .pick : .precision)
        }
        func play(_ m: Int) -> PlanBlock {
            PlanBlock(title: "Play-along", subtitle: "Setlist – mitspielen",
                      minutes: m, systemImage: "music.note.list", target: .songs(.setlist))
        }
        // Kurze Sessions: statt freiem Play-along die kritischen Stellen „im
        // Zusammenhang" (Kontext-Marker); sonst Fallback auf Setlist.
        func contextPlay(_ m: Int) -> PlanBlock {
            guard let p = contextPicks.first else { return play(m) }
            return PlanBlock(title: "Im Zusammenhang · \(p.reason.label)",
                             subtitle: "\(p.count) kritische Stellen mit Anlauf",
                             minutes: m, systemImage: "arrow.turn.down.right",
                             target: .practiceClass(p.reason, contextOnly: true))
        }

        switch length {
        case .s15:
            blocks = [warmup(3), technique(4), problem(0, 5), contextPlay(3)]
        case .s30:
            blocks = [warmup(5), fretboard(5), technique(8), problem(0, 8), contextPlay(4)]
        case .s45:
            blocks = [warmup(6), fretboard(6), technique(9), problem(0, 10), problem(1, 8), play(6)]
        case .s60:
            blocks = [warmup(7), fretboard(8), technique(10), problem(0, 12), problem(1, 10), play(8), problem(2, 5)]
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
        case .practiceClass(let r, let ctx): PracticeClassView(reason: r, contextOnly: ctx)
        case .songs(let s): SongsView(source: s)
        }
    }
}

// MARK: - Session-Block mit Timer + Dialog

/// Uhr für einen Block; feuert nach `seconds`.
@MainActor
final class BlockClock: ObservableObject {
    @Published var remaining = 0
    @Published var finished = false
    private var timer: Timer?

    func start(seconds: Int) {
        stop(); remaining = max(1, seconds); finished = false
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.remaining > 0 { self.remaining -= 1 }
                if self.remaining <= 0 { self.stop(); self.finished = true }
            }
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
                    Text("\(clock.remaining / 60):\(String(format: "%02d", clock.remaining % 60))")
                        .font(.caption).monospacedDigit().fontWeight(.semibold)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.trailing, 12).padding(.top, 6)
                }
                Spacer()
            }
            if clock.finished { dialog }
        }
        .onAppear { clock.start(seconds: minutes * 60) }
        .onDisappear { clock.stop() }
    }

    private var dialog: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Zeit um").font(.title2).bold()
                Text("„\(title)" · \(minutes) min").font(.subheadline).foregroundColor(.secondary)
                HStack(spacing: 12) {
                    Button("Nochmal") { clock.start(seconds: minutes * 60) }
                        .buttonStyle(.bordered).controlSize(.large)
                    Button("Weiter") { onNext() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                Button("Abbrechen", role: .cancel) { onCancel() }
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 20).fill(.regularMaterial))
            .padding(40)
        }
    }
}
