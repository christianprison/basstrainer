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

    func build() async {
        isLoading = true
        defer { isLoading = false }

        // Daten laden.
        let markerStore = PracticeMarkerStore()
        await markerStore.loadAll()
        let allMarkers = markerStore.markers

        let band = UserDefaults.standard.string(forKey: "selectedBandID")
        let setlist = SongCatalog(source: .setlist)
        await setlist.load(bandID: band)
        let setlistIDs = Set(setlist.songs.map { $0.id })

        let log = PracticeLogStore.shared
        if log.entries.isEmpty { await log.load() }

        // Technik-Block wechselt tageweise (Interleaving).
        let weekday = Calendar.current.component(.weekday, from: Date())
        let techniqueIsPick = (weekday % 2 == 0)
        let technique = PlanBlock(
            title: techniqueIsPick ? "Technik · Pick-Oktaven" : "Technik · Präzision",
            subtitle: "Oktaven zum Klick, progressiv schneller",
            minutes: 8, systemImage: "bolt.fill",
            target: techniqueIsPick ? .pick : .precision
        )

        var result: [PlanBlock] = [
            PlanBlock(title: "Warm-up", subtitle: "Orientierung – Quinten/Quarten, langsamer Klick",
                      minutes: 5, systemImage: "flame.fill", target: .orientation),
            PlanBlock(title: "Griffbrett", subtitle: "Pentatonic Shapes – eine Lage",
                      minutes: 5, systemImage: "square.grid.3x3.fill", target: .pentatonic),
            technique,
        ]
        if let problem = topProblem(markers: allMarkers, setlistIDs: setlistIDs, log: log) {
            result.append(problem)
        }
        result.append(PlanBlock(title: "Play-along", subtitle: "Setlist – 1 Song mitspielen",
                                minutes: 4, systemImage: "music.note.list", target: .songs(.setlist)))
        blocks = result
    }

    /// Wählt den dringendsten Marker-Grund: viele Stellen + lange nicht geübt +
    /// Bezug zur aktuellen Setlist.
    private func topProblem(markers: [PracticeMarker], setlistIDs: Set<String>, log: PracticeLogStore) -> PlanBlock? {
        guard !markers.isEmpty else { return nil }
        let byReason = Dictionary(grouping: markers) { $0.reason }
        var best: (reason: PracticeReason, score: Double, count: Int, days: Int?)?
        for (reason, ms) in byReason {
            let count = ms.count
            let setlistHits = ms.filter { setlistIDs.contains($0.songID) }.count
            let days = daysSinceLastPracticed(label: reason.label, log: log)
            let recency = Double(days ?? 30)                 // nie geübt ⇒ wie 30 Tage
            let score = Double(count) + recency * 0.5 + Double(setlistHits) * 2
            if best == nil || score > best!.score {
                best = (reason, score, count, days)
            }
        }
        guard let b = best else { return nil }
        let daysText = b.days.map { $0 == 0 ? "heute schon geübt" : "zuletzt vor \($0) Tg." } ?? "noch nie geübt"
        return PlanBlock(
            title: "Problemstellen · \(b.reason.label)",
            subtitle: "\(b.count) markierte Stellen · \(daysText)",
            minutes: 8, systemImage: b.reason.systemImage,
            target: .practiceClass(b.reason)
        )
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
    @State private var active: PlanTarget?

    var body: some View {
        NavigationStack {
            Group {
                if planner.isLoading && planner.blocks.isEmpty {
                    ProgressView("Stelle deine Session zusammen …").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(planner.blocks) { block in
                                Button { active = block.target } label: { row(block) }
                            }
                        } header: {
                            Text("Heutige Session · \(planner.totalMinutes) min").textCase(nil)
                        } footer: {
                            Text("Automatisch aus Best-Practice-Vorlage + deinen Markern, dem Übungs-Log und der Setlist. Tippe einen Block, um direkt zu starten.")
                        }
                    }
                }
            }
            .navigationTitle("Heute üben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Menü", systemImage: "chevron.left") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await planner.build() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .task { if planner.blocks.isEmpty { await planner.build() } }
            .fullScreenCover(item: $active) { target in
                destination(for: target).logPractice(target.logLabel, active: true)
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
            Image(systemName: "play.circle.fill").font(.title3).foregroundColor(.accentColor)
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
