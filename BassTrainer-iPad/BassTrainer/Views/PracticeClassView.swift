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
                if vm.player.isLooping || vm.loadingSpot || vm.countInBeat > 0 {
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
            if vm.countInBeat > 0 {
                Label("Einzähler … \(vm.countInBeat)", systemImage: "metronome")
                    .font(.title3).fontWeight(.bold).foregroundColor(.orange)
            }
            if vm.loadingSpot { ProgressView() }

            if vm.isSpeed { speedControls }

            HStack(spacing: 16) {
                Button { vm.previous() } label: { Image(systemName: "backward.fill").font(.title3) }
                    .disabled(!vm.hasPrev)
                Spacer()
                if !vm.isSpeed && vm.player.isLooping && vm.player.loopRate < 1.0 {
                    Text("\(Int(vm.player.loopRate * 100)) %").font(.caption).monospacedDigit().foregroundColor(.secondary)
                }
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

    /// Tempo-Steuerung für Geschwindigkeitsstellen: Modus + -/+ + Präzisions-Info.
    private var speedControls: some View {
        VStack(spacing: 10) {
            Picker("Tempo-Modus", selection: Binding(
                get: { vm.speedMode },
                set: { vm.setSpeedMode($0) }
            )) {
                ForEach(SpeedMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 24) {
                Button { vm.nudgeTempo(-0.05) } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 34))
                }
                .disabled(!vm.player.isLooping)
                Text("\(vm.tempoPercent) %")
                    .font(.title2).fontWeight(.semibold).monospacedDigit()
                    .frame(minWidth: 80)
                Button { vm.nudgeTempo(0.05) } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 34))
                }
                .disabled(!vm.player.isLooping)
            }

            if vm.speedMode == .autoPrecision {
                HStack(spacing: 6) {
                    Image(systemName: vm.listening ? "waveform" : "waveform.slash")
                        .foregroundColor(vm.listening ? .green : .secondary)
                    if let s = vm.precisionScore {
                        Text("Präzision \(Int(s * 100)) % · wird bei sauberem Timing schneller")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("Mitspielen (USB-DI) – erhöht nach sauberen Durchläufen")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
            }
        }
    }
}

/// Wie das Tempo beim Üben von Geschwindigkeitsstellen erhöht wird.
enum SpeedMode: String, CaseIterable, Identifiable {
    case manual         // per -/+ Buttons
    case autoTime       // pro Loop-Durchlauf automatisch schneller
    case autoPrecision  // schneller erst nach sauber gespielten Durchläufen

    var id: String { rawValue }
    var label: String {
        switch self {
        case .manual:        return "Manuell"
        case .autoTime:      return "Auto · Zeit"
        case .autoPrecision: return "Auto · Präzision"
        }
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
    // Speed-Übung
    @Published var speedMode: SpeedMode = .manual
    @Published var countInBeat = 0          // 0 = kein Einzähler, 1…4 = laufend
    @Published var precisionScore: Double?  // letzter Tightness-Wert 0…1 (Info)
    @Published var listening = false
    let player = SongPlayer()

    private let store = PracticeMarkerStore()
    private let catalog = SongCatalog(source: .repertoire)
    private let detail = SongDetailViewModel()
    private let audio = AudioEngine()       // Einzähler-Klicks
    private let listener = ListeningEngine() // Onset-Erkennung (USB-DI)
    private var songsByID: [String: CatalogSong] = [:]
    private var cancellables = Set<AnyCancellable>()

    // Präzisions-Messung
    private var onsetTimes: [Double] = []
    private var cleanPasses = 0
    private let startRate: Float = 0.6      // Anfangstempo der Speed-Übung

    var isSpeed: Bool { reason == .speed }

    init(reason: PracticeReason) {
        self.reason = reason
        // Änderungen des Players (isLooping, loopRate) an die View weiterreichen.
        player.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
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
        stopListening()
        currentSpotID = m.id
        loadingSpot = true
        error = nil
        precisionScore = nil
        cleanPasses = 0
        Task {
            await detail.load(songID: m.songID)
            player.load(path: songsByID[m.songID]?.playalongPath)
            loadingSpot = false
            if isSpeed { await countIn(for: m) }
            loopCurrent(m)
            if isSpeed && speedMode == .autoPrecision, player.isLooping { startListening() }
        }
    }

    func next() { if let i = currentIndex, i + 1 < spots.count { play(spots[i + 1]) } }
    func previous() { if let i = currentIndex, i > 0 { play(spots[i - 1]) } }

    /// Vier Klicks im (Start-)Tempo als Einzähler vor dem Loop.
    private func countIn(for m: PracticeMarker) async {
        guard let bpm = songsByID[m.songID]?.bpm, bpm > 0 else { return }
        let interval = (60.0 / Double(bpm)) / Double(startRate)
        for beat in 1...4 {
            countInBeat = beat
            audio.playMetronomeClick(accent: beat == 1)
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        countInBeat = 0
    }

    /// Gleiche Loop-Logik wie im Takte-Raster; Speed-Stellen starten langsam.
    private func loopCurrent(_ m: PracticeMarker) {
        let combo = m.mode == .context && m.reason == .shift
        let leadBars = combo ? 8 : (m.mode == .context ? 2 : 0)
        let trailBars = combo ? 4 : 0
        let startBar = max(1, m.startBar - leadBars)
        let endBar = m.endBar + trailBars
        guard let start = detail.startTime(forBar: startBar) ?? detail.startTime(forBar: m.startBar) else {
            error = "Für „\(songName(m))“ ist kein Timing hinterlegt – Loop nicht möglich."
            return
        }
        let end = detail.endTime(forBar: endBar) ?? detail.endTime(forBar: m.endBar) ?? player.duration
        guard end > start else { return }
        if isSpeed {
            player.onLoopRestart = { [weak self] in self?.evaluatePass(m) }
            player.playLoop(start: start, end: end, progressive: speedMode == .autoTime, startRate: startRate)
        } else {
            player.playLoop(start: start, end: end, progressive: m.mode == .loop)
        }
    }

    // MARK: - Tempo-Steuerung

    func nudgeTempo(_ delta: Float) { player.nudgeRate(by: delta) }
    var tempoPercent: Int { Int((player.loopRate * 100).rounded()) }

    func setSpeedMode(_ mode: SpeedMode) {
        speedMode = mode
        cleanPasses = 0
        guard player.isLooping else { return }
        player.setProgressive(mode == .autoTime)
        if mode == .autoPrecision { startListening() } else { stopListening() }
    }

    // MARK: - Präzisions-Messung (Onsets vom USB-Eingang)

    private func startListening() {
        onsetTimes.removeAll()
        listener.onOnset = { [weak self] time, _ in
            Task { @MainActor in self?.onsetTimes.append(time) }
        }
        listener.start { [weak self] ok in
            Task { @MainActor in self?.listening = ok }
        }
    }

    private func stopListening() {
        listener.onOnset = nil
        listener.stop()
        listening = false
    }

    /// Am Ende jedes Loop-Durchlaufs: Timing-„Tightness“ der Anschläge messen.
    /// Sauber = Anschlagabstände liegen nah am 16tel-Raster des aktuellen Tempos.
    private func evaluatePass(_ m: PracticeMarker) {
        guard speedMode == .autoPrecision else { onsetTimes.removeAll(); return }
        let onsets = onsetTimes
        onsetTimes.removeAll()
        guard let bpm = songsByID[m.songID]?.bpm, bpm > 0, onsets.count >= 4 else {
            cleanPasses = 0; return
        }
        let sixteenth = (60.0 / Double(bpm)) / Double(player.loopRate) / 4.0
        var devSum = 0.0
        var count = 0
        for i in 1..<onsets.count {
            let ioi = onsets[i] - onsets[i - 1]
            guard ioi > sixteenth * 0.5 else { continue }        // Doppeltrigger überspringen
            let mult = (ioi / sixteenth).rounded()
            guard mult >= 1 else { continue }
            devSum += min(1.0, abs(ioi - mult * sixteenth) / sixteenth)
            count += 1
        }
        guard count >= 3 else { cleanPasses = 0; return }
        let tightness = max(0, 1 - devSum / Double(count))
        precisionScore = tightness
        if tightness >= 0.8 {
            cleanPasses += 1
            if cleanPasses >= 2 {           // zwei saubere Durchläufe → schneller
                cleanPasses = 0
                player.nudgeRate(by: 0.05)
            }
        } else {
            cleanPasses = 0
        }
    }

    func stopLoop() {
        player.clearLoop()
        player.pause()
        stopListening()
    }

    func stopAll() {
        player.stop()
        stopListening()
    }
}
