import SwiftUI
import Combine

/// Übungskapitel für eine Marker-Kategorie: alle markierten Stellen dieser
/// „Klasse" songübergreifend durchüben (jede Stelle als Loop, gleiche Logik
/// wie im Takte-Raster — inkl. Anlauf bei „Zusammenhang"/„Lagenwechsel").
struct PracticeClassView: View {
    let reason: PracticeReason
    @StateObject private var vm: PracticeClassViewModel
    @Environment(\.dismiss) private var dismiss

    init(reason: PracticeReason) {
        self.reason = reason
        _vm = StateObject(wrappedValue: PracticeClassViewModel(reason: reason))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                if vm.player.isLooping || vm.loadingSpot || vm.speed.countInBeat > 0 {
                    Divider()
                    nowPlayingBar
                }
            }
            .navigationTitle(reason.label)
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
        if vm.isLoading {
            ProgressView("Lade markierte Stellen …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.spots.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: reason.systemImage).font(.system(size: 40)).foregroundColor(reason.color)
                Text("Keine Stellen in „\(reason.label)“").font(.headline)
                Text("Markiere Stellen im Repertoire → Takte mit dem Grund „\(reason.label)“.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                if let e = vm.error { Text(e).font(.caption2).foregroundColor(.red).multilineTextAlignment(.center) }
            }
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(vm.spots) { spot in
                Button { vm.play(spot) } label: { spotRow(spot) }
                    .listRowBackground(vm.currentSpotID == spot.id ? reason.color.opacity(0.12) : Color(.systemBackground))
            }
            .listStyle(.plain)
        }
    }

    private func spotRow(_ spot: PracticeMarker) -> some View {
        HStack(spacing: 10) {
            Image(systemName: spot.mode.systemImage).foregroundColor(reason.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.songName(spot)).font(.subheadline).foregroundColor(.primary)
                Text("Takt \(spot.startBar)–\(spot.endBar) · \(spot.mode.shortLabel)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: vm.currentSpotID == spot.id && vm.player.isLooping ? "repeat.circle.fill" : "play.circle")
                .foregroundColor(vm.currentSpotID == spot.id && vm.player.isLooping ? reason.color : .secondary)
        }
        .contentShape(Rectangle())
    }

    private var nowPlayingBar: some View {
        VStack(spacing: 8) {
            if let m = vm.currentSpot {
                Text("\(vm.songName(m)) · Takt \(m.startBar)–\(m.endBar)")
                    .font(.subheadline).fontWeight(.semibold).lineLimit(1)
            }
            if vm.loadingSpot { ProgressView() }

            SpeedTrainerBar(trainer: vm.speed, isLooping: vm.player.isLooping)

            HStack(spacing: 16) {
                Button { vm.previous() } label: { Image(systemName: "backward.fill").font(.title3) }
                    .disabled(!vm.hasPrev)
                Spacer()
                Button { vm.stopLoop() } label: {
                    Label("Loop aus", systemImage: "stop.circle.fill").font(.headline)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(.red)
                .disabled(!vm.player.isLooping)
                Spacer()
                Button { vm.next() } label: { Image(systemName: "forward.fill").font(.title3) }
                    .disabled(!vm.hasNext)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - ViewModel

@MainActor
final class PracticeClassViewModel: ObservableObject {
    let reason: PracticeReason

    @Published var spots: [PracticeMarker] = []
    @Published var isLoading = true
    @Published var error: String?
    @Published var currentSpotID: UUID?
    @Published var loadingSpot = false
    let player = SongPlayer()
    let speed = SpeedTrainer()

    private let store = PracticeMarkerStore()
    private let catalog = SongCatalog(source: .repertoire)
    private let detail = SongDetailViewModel()
    private var songsByID: [String: CatalogSong] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(reason: PracticeReason) {
        self.reason = reason
        // Änderungen von Player und Speed-Trainer an die View weiterreichen.
        player.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        speed.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var currentSpot: PracticeMarker? { spots.first { $0.id == currentSpotID } }
    private var currentIndex: Int? { spots.firstIndex { $0.id == currentSpotID } }
    var hasPrev: Bool { (currentIndex ?? 0) > 0 }
    var hasNext: Bool { if let i = currentIndex { return i < spots.count - 1 }; return false }

    func load() async {
        isLoading = true
        error = nil
        await catalog.load()
        songsByID = Dictionary(catalog.songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        spots = await store.markers(forReason: reason)
        if spots.isEmpty { error = store.syncError }
        isLoading = false
    }

    func songName(_ m: PracticeMarker) -> String { songsByID[m.songID]?.name ?? m.songID }

    func play(_ m: PracticeMarker) {
        speed.stop()
        currentSpotID = m.id
        loadingSpot = true
        error = nil
        Task {
            await detail.load(songID: m.songID)
            player.load(path: songsByID[m.songID]?.playalongPath)
            speed.configure(player: player, bpm: songsByID[m.songID]?.bpm ?? 120)
            loadingSpot = false
            // „Im Zusammenhang“ startet auf Originaltempo, reiner Loop langsam.
            let startRate: Float = m.mode == .context ? 1.0 : 0.6
            await speed.countIn(rate: startRate)   // Einzähler vor jedem Loop
            loopCurrent(m, startRate: startRate)
            if player.isLooping { speed.loopStarted() }
        }
    }

    func next() { if let i = currentIndex, i + 1 < spots.count { play(spots[i + 1]) } }
    func previous() { if let i = currentIndex, i > 0 { play(spots[i - 1]) } }

    /// Gleiche Loop-Logik wie im Takte-Raster.
    private func loopCurrent(_ m: PracticeMarker, startRate: Float) {
        let combo = m.mode == .context && m.reason == .shift
        let context = m.mode == .context
        let leadBars = combo ? 8 : (context ? 2 : 0)
        let trailBars = combo ? 4 : (context ? 2 : 0)   // im Zusammenhang min. 2 Takte Auslauf
        let startBar = max(1, m.startBar - leadBars)
        let endBar = m.endBar + trailBars
        guard let start = detail.startTime(forBar: startBar) ?? detail.startTime(forBar: m.startBar) else {
            error = "Für „\(songName(m))“ ist kein Timing hinterlegt – Loop nicht möglich."
            return
        }
        let end = detail.endTime(forBar: endBar) ?? detail.endTime(forBar: m.endBar) ?? player.duration
        guard end > start else { return }
        player.playLoop(start: start, end: end, progressive: speed.mode == .autoTime, startRate: startRate)
    }

    func stopLoop() {
        player.clearLoop()
        player.pause()
        speed.stop()
    }

    func stopAll() {
        player.stop()
        speed.stop()
    }
}
