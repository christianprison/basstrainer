import SwiftUI
import AVFoundation

/// Repertoire-Übung „Übergänge": übt die Song-Wechsel der Setlist. Pro Übergang
/// werden die letzten 2 Parts des Songs, ein kurzer Applaus-Einspieler und die
/// ersten 2 Parts des nächsten Songs abgespielt – so wie live auf der Bühne.
struct TransitionsView: View {
    @StateObject private var vm = TransitionsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Lade Setlist …").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.transitions.isEmpty {
                    Text("Keine Übergänge – die Setlist hat weniger als 2 Songs.")
                        .foregroundColor(.secondary).padding()
                } else {
                    content
                }
            }
            .navigationTitle("Übergänge")
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
                    ForEach(Array(vm.transitions.enumerated()), id: \.element.id) { i, tr in
                        Button { vm.play(i) } label: { row(i, tr) }
                    }
                } header: {
                    Text("\(vm.transitions.count) Übergänge · letzte 2 Parts → 👏 → erste 2 Parts").textCase(nil)
                }
            }
        }
    }

    private func row(_ i: Int, _ tr: TransitionsViewModel.Transition) -> some View {
        HStack(spacing: 12) {
            Text("\(i + 1)").font(.caption).monospacedDigit().foregroundColor(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(tr.from.name) → \(tr.to.name)").font(.subheadline).fontWeight(.medium)
                Text("\(tr.from.artist ?? "")  →  \(tr.to.artist ?? "")").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: vm.selectedIndex == i && vm.isActive ? "waveform.circle.fill" : "play.circle.fill")
                .font(.title3).foregroundColor(.accentColor)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var nowPlaying: some View {
        VStack(spacing: 8) {
            if let tr = vm.current {
                Text("\(tr.from.name) → \(tr.to.name)").font(.headline).lineLimit(1)
            } else {
                Text("Übergang wählen").font(.headline).foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                phaseChip("Ende", .playingA, "backward.end.fill")
                Image(systemName: "arrow.right").font(.caption2).foregroundColor(.secondary)
                phaseChip("Applaus", .applause, "hands.clap.fill")
                Image(systemName: "arrow.right").font(.caption2).foregroundColor(.secondary)
                phaseChip("Anfang", .playingB, "forward.end.fill")
            }
            if let s = vm.status { Text(s).font(.caption2).foregroundColor(.secondary) }
            if vm.isActive {
                Button(role: .destructive) { vm.stop() } label: {
                    Label("Stopp", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
    }

    private func phaseChip(_ title: String, _ phase: TransitionsViewModel.Phase, _ icon: String) -> some View {
        let active = vm.phase == phase
        return Label(title, systemImage: icon)
            .font(.caption).fontWeight(active ? .bold : .regular)
            .foregroundColor(active ? .accentColor : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(active ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground)))
    }
}

// MARK: - ViewModel

@MainActor
final class TransitionsViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, playingA, applause, playingB, done }

    struct Transition: Identifiable {
        let from: CatalogSong
        let to: CatalogSong
        var id: String { "\(from.id)->\(to.id)" }
    }

    @Published var transitions: [Transition] = []
    @Published var isLoading = false
    @Published var phase: Phase = .idle
    @Published var selectedIndex: Int?
    @Published var status: String?

    private let audio = AudioEngine()
    private let player = TransitionPlayer()
    private let applauseSeconds = 2.6

    var isActive: Bool { phase == .playingA || phase == .applause || phase == .playingB }
    var current: Transition? { selectedIndex.flatMap { transitions.indices.contains($0) ? transitions[$0] : nil } }

    func load() async {
        guard transitions.isEmpty else { return }
        isLoading = true
        let band = UserDefaults.standard.string(forKey: "selectedBandID")
        let catalog = SongCatalog(source: .setlist)
        await catalog.load(bandID: band)
        let songs = catalog.songs
        transitions = zip(songs, songs.dropFirst()).map { Transition(from: $0, to: $1) }
        isLoading = false
    }

    func play(_ idx: Int) {
        guard transitions.indices.contains(idx) else { return }
        stop()
        selectedIndex = idx
        let tr = transitions[idx]
        status = nil
        guard let aPath = tr.from.playalongPath, let aURL = SupabaseConfig.publicAudioURL(for: aPath) else {
            status = "Kein Play-along für „\(tr.from.name)"."; phase = .idle; return
        }
        guard let bPath = tr.to.playalongPath, let bURL = SupabaseConfig.publicAudioURL(for: bPath) else {
            status = "Kein Play-along für „\(tr.to.name)"."; phase = .idle; return
        }
        phase = .loading
        Task {
            let aTail = await tailStart(songID: tr.from.id, durationSec: tr.from.durationSec)
            let bHead = await headEnd(songID: tr.to.id, durationSec: tr.to.durationSec)
            guard selectedIndex == idx else { return }   // zwischendurch gewechselt
            phase = .playingA
            player.playSegment(url: aURL, from: aTail, to: nil) { [weak self] in
                guard let self, self.phase == .playingA else { return }
                self.phase = .applause
                self.audio.playApplause()
                DispatchQueue.main.asyncAfter(deadline: .now() + self.applauseSeconds) { [weak self] in
                    guard let self, self.phase == .applause else { return }
                    self.phase = .playingB
                    self.player.playSegment(url: bURL, from: 0, to: bHead) { [weak self] in
                        self?.phase = .done
                    }
                }
            }
        }
    }

    func stop() {
        player.stop()
        if phase != .idle { phase = .idle }
    }

    // MARK: Part-Zeiten

    private func partData(_ songID: String) async -> (parts: [SongPart], barTime: [Int: Double]) {
        let idFilter = URLQueryItem(name: "song_id", value: "eq.\(songID)")
        let parts: [SongPart] = (try? await SupabaseConfig.get(
            path: "song_parts_public",
            query: [idFilter, URLQueryItem(name: "order", value: "start_bar.asc")])) ?? []
        let tl: [TimelineBar] = (try? await SupabaseConfig.get(
            path: "song_timeline_public",
            query: [idFilter, URLQueryItem(name: "order", value: "bar_num.asc")])) ?? []
        var m: [Int: Double] = [:]
        for b in tl { m[b.barNum] = b.tStart }
        return (parts, m)
    }

    /// Startzeit der vorletzten Part (= Beginn der letzten 2 Parts).
    private func tailStart(songID: String, durationSec: Int?) async -> Double {
        let (parts, barTime) = await partData(songID)
        if parts.count >= 2, let t = barTime[parts[parts.count - 2].startBar] { return t }
        if let d = durationSec { return max(0, Double(d) - 30) }
        return 0
    }

    /// Endzeit nach den ersten 2 Parts (= Beginn der 3. Part), sonst Songende.
    private func headEnd(songID: String, durationSec: Int?) async -> Double? {
        let (parts, barTime) = await partData(songID)
        if parts.count >= 3, let t = barTime[parts[2].startBar] { return t }
        if let d = durationSec { return Double(d) }   // <3 Parts → ganzen Anfang spielen
        return nil                                    // unbekannt → bis Songende
    }
}

// MARK: - Sequenzieller Segment-Player

/// Spielt genau einen Abschnitt einer Audiodatei (von `from` bis `to`, oder bis
/// zum Dateiende) und ruft danach `onEnd` auf.
@MainActor
final class TransitionPlayer: ObservableObject {
    private var player: AVPlayer?
    private var timeObs: Any?
    private var endObs: NSObjectProtocol?
    private var segEnd = Double.infinity
    private var onEnd: (() -> Void)?

    func playSegment(url: URL, from: Double, to: Double?, onEnd: @escaping () -> Void) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        segEnd = to ?? .infinity
        self.onEnd = onEnd

        endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        timeObs = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                if time.seconds >= self.segEnd { self.fire() }
            }
        }
        p.seek(to: CMTime(seconds: max(0, from), preferredTimescale: 600)) { _ in
            DispatchQueue.main.async { p.play() }
        }
    }

    private func fire() {
        let cb = onEnd
        onEnd = nil
        segEnd = .infinity
        player?.pause()
        cb?()
    }

    func stop() {
        if let timeObs { player?.removeTimeObserver(timeObs) }
        timeObs = nil
        if let endObs { NotificationCenter.default.removeObserver(endObs) }
        endObs = nil
        onEnd = nil
        segEnd = .infinity
        player?.pause()
        player = nil
    }
}

#Preview {
    TransitionsView()
}
