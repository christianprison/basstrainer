import SwiftUI

/// Ziel eines Plan-Blocks – bestimmt, welche Übung direkt gestartet wird.
enum PlanTarget: Identifiable, Equatable {
    case orientation
    case pentatonic
    case pick
    case precision
    case practiceClass(PracticeReason)
    case songs(SongSource)

    var id: String {
        switch self {
        case .orientation: return "orientation"
        case .pentatonic:  return "pentatonic"
        case .pick:        return "pick"
        case .precision:   return "precision"
        case .practiceClass(let r): return "pc-\(r.rawValue)"
        case .songs(let s): return "songs-\(s == .setlist ? "set" : "rep")"
        }
    }

    /// Label fürs Übungs-Log (identisch zu den Menü-Labels → konsistente Kategorien).
    var logLabel: String {
        switch self {
        case .orientation: return "Orientierung"
        case .pentatonic:  return "Pentatonic Shapes"
        case .pick:        return "Pick"
        case .precision:   return "Oktaven"
        case .practiceClass(let r): return r.label
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
                             minutes: min, systemImage: p.reason.systemImage, target: .practiceClass(p.reason))
        }
        func warmup(_ m: Int) -> PlanBlock {
            PlanBlock(title: "Warm-up", subtitle: "Orientierung – Quinten/Quarten, langsamer Klick",
                      minutes: m, systemImage: "flame.fill", target: .orientation)
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

        switch length {
        case .s15:
            blocks = [warmup(3), technique(4), problem(0, 5), play(3)]
        case .s30:
            blocks = [warmup(5), fretboard(5), technique(8), problem(0, 8), play(4)]
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
    @State private var active: PlanTarget?
    @State private var lastStarted: PlanTarget?
    @State private var done: Set<String> = []

    private var length: SessionLength { SessionLength(rawValue: lengthRaw) ?? .s30 }

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
            .fullScreenCover(item: $active, onDismiss: {
                // Zurück aus der Übung → Block als erledigt markieren.
                if let t = lastStarted { done.insert(t.id) }
            }) { target in
                destination(for: target).logPractice(target.logLabel, active: true)
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
                    ForEach(planner.blocks) { block in
                        Button { lastStarted = block.target; active = block.target } label: { row(block) }
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
        case .orientation: OrientationView()
        case .pentatonic:  PentatonicView()
        case .pick:        PickOctavesView()
        case .precision:   PrecisionOctavesView()
        case .practiceClass(let r): PracticeClassView(reason: r)
        case .songs(let s): SongsView(source: s)
        }
    }
}
