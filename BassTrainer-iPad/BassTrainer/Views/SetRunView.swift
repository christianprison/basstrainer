import SwiftUI
import AVFoundation

/// Repertoire-Übung „Set-Durchlauf": spielt die ganze aktuelle Setlist im
/// Schnelldurchlauf. Pro Song: Anfang bis der erste sich wiederholende Teil
/// (typischerweise der Chorus) einsetzt → Sprung (ohne Preroll) direkt zur
/// letzten Wiederholung dieses Teils → bis Songende → Applaus einblenden und
/// parallel den nächsten Song starten. Teile mit Nummern zählen als gleich.
struct SetRunView: View {
    @StateObject private var vm = SetRunViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Lade Setlist …").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.songs.isEmpty {
                    Text("Keine Songs in der aktuellen Setlist.").foregroundColor(.secondary).padding()
                } else {
                    content
                }
            }
            .navigationTitle("Set-Durchlauf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { vm.stop(); dismiss() } label: { Label("Menü", systemImage: "chevron.left") }
                }
            }
        }
        .task { await vm.load() }
        .onDisappear { vm.stop() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            nowPlaying
            Divider()
            List {
                Section {
                    ForEach(Array(vm.songs.enumerated()), id: \.element.id) { i, song in
                        row(i, song)
                    }
                } header: {
                    Text("\(vm.songs.count) Songs · Anfang → letzter Teil → Applaus → nächster").textCase(nil)
                }
            }
        }
    }

    private var nowPlaying: some View {
        VStack(spacing: 10) {
            if vm.isRunning, vm.songs.indices.contains(vm.index) {
                Text("\(vm.index + 1)/\(vm.songs.count) · \(vm.songs[vm.index].name)")
                    .font(.headline).lineLimit(1)
                Text(vm.phaseLabel).font(.caption).foregroundColor(.accentColor)
                ProgressView(value: vm.duration > 0 ? min(1, vm.progress / vm.duration) : 0)
                    .tint(.accentColor).padding(.horizontal, 24)
            } else {
                Text("Bereit für den Set-Durchlauf").font(.headline).foregroundColor(.secondary)
            }
            Button {
                vm.isRunning ? vm.stop() : vm.start()
            } label: {
                Label(vm.isRunning ? "Stopp" : "Set starten",
                      systemImage: vm.isRunning ? "stop.fill" : "play.fill")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .tint(vm.isRunning ? .red : .accentColor)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 12)
    }

    private func row(_ i: Int, _ song: CatalogSong) -> some View {
        HStack(spacing: 12) {
            Text("\(i + 1)").font(.caption).monospacedDigit().foregroundColor(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.name).font(.subheadline).fontWeight(i == vm.index && vm.isRunning ? .bold : .regular)
                if let a = song.artist { Text(a).font(.caption2).foregroundColor(.secondary) }
            }
            Spacer()
            if !song.hasPlayalong {
                Image(systemName: "speaker.slash").font(.caption).foregroundColor(.secondary)
            } else if i == vm.index && vm.isRunning {
                Image(systemName: "waveform").foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { vm.start(at: i) }
    }
}

// MARK: - ViewModel

@MainActor
final class SetRunViewModel: ObservableObject {
    enum Phase { case idle, loading, intro, ending }

    @Published var songs: [CatalogSong] = []
    @Published var isLoading = false
    @Published var isRunning = false
    @Published var index = 0
    @Published var phase: Phase = .idle
    @Published var progress = 0.0
    @Published var duration = 0.0

    private let audio = AudioEngine()
    private var player: AVPlayer?
    private var timeObs: Any?
    private var endObs: NSObjectProtocol?
    private var seg2Start = 0.0
    private var pendingJump: Double?

    var phaseLabel: String {
        switch phase {
        case .loading: return "lädt …"
        case .intro:   return "Anfang → bis zum wiederkehrenden Schlussteil"
        case .ending:  return "Schluss ab der letzten Wiederholung"
        case .idle:    return ""
        }
    }

    func load() async {
        guard songs.isEmpty else { return }
        isLoading = true
        let band = UserDefaults.standard.string(forKey: "selectedBandID")
        let catalog = SongCatalog(source: .setlist)
        await catalog.load(bandID: band)
        songs = catalog.songs
        isLoading = false
    }

    func start(at i: Int = 0) {
        guard songs.indices.contains(i) else { return }
        stop()
        index = i
        isRunning = true
        playCurrent()
    }

    func stop() {
        teardownPlayer()
        isRunning = false
        phase = .idle
        progress = 0; duration = 0
    }

    // MARK: Ablauf

    private func playCurrent() {
        guard isRunning, songs.indices.contains(index) else { finish(); return }
        let song = songs[index]
        phase = .loading
        Task {
            let seg = await segments(for: song)
            guard isRunning, songs.indices.contains(index), songs[index].id == song.id else { return }
            guard let path = song.playalongPath, let url = SupabaseConfig.publicAudioURL(for: path) else {
                songFinished()   // kein Audio → wie Songende (Applaus + weiter)
                return
            }
            startPlayback(url: url, jumpAt: seg.jumpAt, seg2Start: seg.seg2Start)
        }
    }

    private func startPlayback(url: URL, jumpAt: Double?, seg2Start: Double) {
        teardownPlayer()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = false   // schneller Wiedereinstieg nach dem Sprung
        player = p
        self.seg2Start = seg2Start
        self.pendingJump = jumpAt
        phase = (jumpAt != nil) ? .intro : .ending
        progress = 0; duration = 0

        endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.songFinished() }
        }
        timeObs = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.progress = time.seconds
                if let d = self.player?.currentItem?.duration.seconds, d.isFinite { self.duration = d }
                if let j = self.pendingJump, time.seconds >= j { self.doJump() }
            }
        }
        p.seek(to: .zero) { _ in DispatchQueue.main.async { p.play() } }
    }

    /// Sprung (ohne Preroll) zur letzten Wiederholung.
    private func doJump() {
        guard let p = player else { return }
        pendingJump = nil
        phase = .ending
        p.seek(to: CMTime(seconds: seg2Start, preferredTimescale: 600),
               toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async { p.play() }
        }
    }

    private func songFinished() {
        guard isRunning else { return }
        audio.playApplause()                 // Applaus einblenden …
        if index >= songs.count - 1 { finish(); return }
        index += 1
        playCurrent()                        // … und parallel den nächsten Song starten
    }

    private func finish() {
        teardownPlayer()
        isRunning = false
        phase = .idle
    }

    private func teardownPlayer() {
        if let timeObs { player?.removeTimeObserver(timeObs) }
        timeObs = nil
        if let endObs { NotificationCenter.default.removeObserver(endObs) }
        endObs = nil
        player?.pause()
        player = nil
        pendingJump = nil
    }

    // MARK: Segmente

    /// Basisname eines Teils ohne angehängte Nummer (z. B. „Chorus 2" → „chorus").
    private func base(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\d+\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    /// Maßgeblich ist der LETZTE Teil, der eine Wiederholung eines früheren ist
    /// (typischerweise der End-Chorus). Gespielt wird bis zum Beginn seiner
    /// ersten Instanz, dann Sprung direkt zu seiner letzten Instanz.
    /// jumpAt = Beginn der ersten Instanz, seg2Start = Beginn der letzten.
    /// jumpAt == nil ⇒ ganzen Song spielen.
    private func segments(for song: CatalogSong) async -> (jumpAt: Double?, seg2Start: Double) {
        let id = URLQueryItem(name: "song_id", value: "eq.\(song.id)")
        let parts: [SongPart] = (try? await SupabaseConfig.get(
            path: "song_parts_public",
            query: [id, URLQueryItem(name: "order", value: "start_bar.asc")])) ?? []
        let tl: [TimelineBar] = (try? await SupabaseConfig.get(
            path: "song_timeline_public",
            query: [id, URLQueryItem(name: "order", value: "bar_num.asc")])) ?? []
        guard parts.count >= 2, !tl.isEmpty else { return (nil, 0) }

        var barTime: [Int: Double] = [:]
        for b in tl { barTime[b.barNum] = b.tStart }
        let bases = parts.map { base($0.name) }

        // Letzte Part-Instanz, die eine Wiederholung eines früheren Teils ist.
        var lastRep: Int?
        for i in bases.indices.reversed() where bases[0..<i].contains(bases[i]) { lastRep = i; break }
        guard let li = lastRep, let fi = bases.firstIndex(of: bases[li]),
              let jump = barTime[parts[fi].startBar],
              let s2 = barTime[parts[li].startBar], s2 > jump + 1 else { return (nil, 0) }
        return (jump, s2)
    }
}

#Preview {
    SetRunView()
}
