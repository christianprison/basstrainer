import SwiftUI
import AVFoundation

/// Play-along-Player: streamt den Full-Song-Track aus dem öffentlichen Bucket.
struct SongPlayerView: View {
    let song: Song
    @StateObject private var player = SongPlayer()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 6) {
                Text(song.name).font(.title).fontWeight(.bold).multilineTextAlignment(.center)
                if let artist = song.artist { Text(artist).font(.headline).foregroundColor(.secondary) }
                HStack(spacing: 12) {
                    if let bpm = song.bpm { Label("\(bpm) BPM", systemImage: "metronome") }
                    if let key = song.musicKey { Label(key, systemImage: "music.note") }
                }
                .font(.caption).foregroundColor(.secondary).padding(.top, 4)
            }

            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundColor(.accentColor.opacity(0.6))
                .padding(.vertical, 8)

            // Fortschritt
            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { player.progress },
                    set: { player.seek(to: $0) }
                ), in: 0...max(player.duration, 0.1))
                HStack {
                    Text(timeString(player.progress)).font(.caption2).monospacedDigit()
                    Spacer()
                    Text(timeString(player.duration)).font(.caption2).monospacedDigit()
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // Transport
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            if let err = player.error {
                Text(err).font(.caption).foregroundColor(.red).multilineTextAlignment(.center).padding(.horizontal)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Play-along")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let path = song.playalongPath, let url = SupabaseConfig.publicAudioURL(for: path) {
                player.load(url: url)
            } else {
                player.error = "Für diesen Song gibt es keinen Play-along-Track."
            }
        }
        .onDisappear { player.stop() }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

@MainActor
final class SongPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?

    private var player: AVPlayer?
    private var timeObserver: Any?

    func load(url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.progress = time.seconds
                if let d = self.player?.currentItem?.duration.seconds, d.isFinite {
                    self.duration = d
                }
            }
        }
    }

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        progress = seconds
    }

    func stop() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player = nil
        isPlaying = false
    }
}
