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
    private var playerA: AVPlayer?          // Anfang (bis zum Sprung)
    private var playerB: AVPlayer?          // Schluss (ab letzter Wiederholung)
    private var obsA: Any?
    private var obsB: Any?
    private var endObs: NSObjectProtocol?
    private var fadeTimer: Timer?
    private var seg2Start = 0.0
    private var pendingJump: Double?
    private var jumped = false
    private let crossfadeSeconds = 0.5

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

        let itemA = AVPlayerItem(url: url)
        let a = AVPlayer(playerItem: itemA)
        a.automaticallyWaitsToMinimizeStalling = false
        playerA = a
        self.seg2Start = seg2Start
        self.pendingJump = jumpAt
        self.jumped = false
        phase = (jumpAt != nil) ? .intro : .ending
        progress = 0; duration = 0

        // Schluss-Player vorbereiten und schon zur Zielstelle puffern (2. Stream),
        // damit der Sprung ohne Nachladen und mit Crossfade weich läuft.
        if jumpAt != nil {
            let itemB = AVPlayerItem(url: url)
            let b = AVPlayer(playerItem: itemB)
            b.automaticallyWaitsToMinimizeStalling = false
            b.volume = 0
            playerB = b
            b.seek(to: CMTime(seconds: seg2Start, preferredTimescale: 600))
            endObs = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: itemB, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.songFinished() }
            }
            obsB = b.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    guard let self, self.jumped else { return }
                    self.progress = time.seconds
                    if let d = self.playerB?.currentItem?.duration.seconds, d.isFinite { self.duration = d }
                }
            }
        } else {
            endObs = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: itemA, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.songFinished() }
            }
        }

        obsA = a.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.jumped else { return }
                self.progress = time.seconds
                if let d = self.playerA?.currentItem?.duration.seconds, d.isFinite { self.duration = d }
                if let j = self.pendingJump, time.seconds >= j { self.crossfadeToEnding() }
            }
        }
        a.seek(to: .zero) { _ in DispatchQueue.main.async { a.play() } }
    }

    /// Weicher Übergang: Schluss-Player einblenden, Anfang ausblenden.
    private func crossfadeToEnding() {
        guard !jumped, let a = playerA, let b = playerB else { return }
        jumped = true
        pendingJump = nil
        phase = .ending
        b.volume = 0
        b.play()
        let steps = 20
        let interval = crossfadeSeconds / Double(steps)
        var i = 0
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                i += 1
                let x = Float(i) / Float(steps)
                self.playerA?.volume = 1 - x
                self.playerB?.volume = x
                if i >= steps {
                    t.invalidate()
                    self.fadeTimer = nil
                    self.playerA?.pause()
                    self.playerA?.volume = 1
                }
            }
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
        fadeTimer?.invalidate(); fadeTimer = nil
        if let obsA { playerA?.removeTimeObserver(obsA) }
        obsA = nil
        if let obsB { playerB?.removeTimeObserver(obsB) }
        obsB = nil
        if let endObs { NotificationCenter.default.removeObserver(endObs) }
        endObs = nil
        playerA?.pause(); playerA = nil
        playerB?.pause(); playerB = nil
        pendingJump = nil
        jumped = false
    }

    // MARK: Segmente

    /// Basisname eines Teils ohne angehängte Nummer (z. B. „Chorus 2" → „chorus").
    private func base(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\d+\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    /// Wählt unter allen wiederholten Teilen den Sprung, der am MEISTEN Song
    /// überspringt: für jeden Teil, der mehrfach vorkommt, die Lücke zwischen
    /// erster und letzter Instanz; die größte gewinnt. jumpAt = Beginn der
    /// ersten Instanz, seg2Start = Beginn der letzten. nil ⇒ ganzen Song spielen.
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

        var bestJump: Double?
        var bestSeg2 = 0.0
        var bestGap = 1.0   // mind. > 1 s Ersparnis, sonst lohnt der Sprung nicht
        for b in Set(bases) {
            let idxs = bases.indices.filter { bases[$0] == b }
            guard idxs.count >= 2, let fi = idxs.first, let li = idxs.last,
                  let j = barTime[parts[fi].startBar], let s2 = barTime[parts[li].startBar] else { continue }
            let gap = s2 - j
            if gap > bestGap { bestGap = gap; bestJump = j; bestSeg2 = s2 }
        }
        guard let jump = bestJump else { return (nil, 0) }
        return (jump, bestSeg2)
    }
}

#Preview {
    SetRunView()
}
