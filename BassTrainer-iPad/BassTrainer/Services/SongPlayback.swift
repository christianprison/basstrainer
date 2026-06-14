import Foundation
import AVFoundation

/// Streamt den Play-along-Track (Full-Song-MP3) aus dem öffentlichen Bucket
/// und veröffentlicht die laufende Wiedergabezeit.
@MainActor
final class SongPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?
    @Published private(set) var hasTrack = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var loop: (start: Double, end: Double)?

    /// Lädt einen neuen Track (oder leert den Player, wenn kein Pfad vorhanden).
    func load(path: String?) {
        stop()
        guard let path, let url = SupabaseConfig.publicAudioURL(for: path) else {
            hasTrack = false
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        hasTrack = true
        error = nil
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = time.seconds
                // Loop: zurück zum Anfang, sobald das Ende der markierten Stelle erreicht ist.
                if let loop = self.loop, t >= loop.end {
                    self.seek(to: loop.start)
                    return
                }
                self.progress = t
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

    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Spielt die markierte Stelle als Endlosschleife.
    func playLoop(start: Double, end: Double) {
        guard player != nil, end > start else { return }
        loop = (start, end)
        seek(to: start)
        if !isPlaying { toggle() }
    }

    /// Beendet den Loop (normale Wiedergabe läuft weiter).
    func clearLoop() { loop = nil }

    var isLooping: Bool { loop != nil }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        progress = seconds
    }

    func stop() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player = nil
        loop = nil
        isPlaying = false
        progress = 0
        duration = 0
    }
}

/// Einfaches Metronom (Timer + synthetisierter Klick) im Tempo des Songs.
@MainActor
final class Metronome: ObservableObject {
    @Published var isRunning = false
    @Published var beat = 0
    var bpm: Int = 120

    private let audio = AudioEngine()
    private var timer: Timer?

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard bpm > 0 else { return }
        stop()
        isRunning = true
        beat = 0
        audio.playMetronomeClick(accent: true)
        let interval = 60.0 / Double(bpm)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.beat += 1
                self.audio.playMetronomeClick(accent: self.beat % 4 == 0)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
}
