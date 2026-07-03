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
    @Published private(set) var loopRate: Float = 1.0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var loop: (start: Double, end: Double)?
    private var loopProgressive = false
    private let minLoopRate: Float = 0.6
    private let rateStep: Float = 0.1

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
        item.audioTimePitchAlgorithm = .timeDomain   // Tonhöhe bei Tempoänderung halten
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
                // Loop: am Ende zurück zum Anfang; im progressiven Modus Tempo anheben.
                if let loop = self.loop, t >= loop.end {
                    if self.loopProgressive {
                        self.loopRate = min(1.0, self.loopRate + self.rateStep)
                    }
                    self.player?.seek(to: CMTime(seconds: loop.start, preferredTimescale: 600))
                    self.player?.rate = self.loopRate
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
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.rate = (loop != nil) ? loopRate : 1.0
            isPlaying = true
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Spielt die markierte Stelle als Schleife. `progressive` = langsam → schneller.
    func playLoop(start: Double, end: Double, progressive: Bool) {
        guard let player, end > start else { return }
        loop = (start, end)
        loopProgressive = progressive
        loopRate = progressive ? minLoopRate : 1.0
        seek(to: start)
        player.rate = loopRate
        isPlaying = true
    }

    /// Beendet den Loop (normale Wiedergabe läuft in Originaltempo weiter).
    func clearLoop() {
        loop = nil
        loopProgressive = false
        loopRate = 1.0
        if isPlaying { player?.rate = 1.0 }
    }

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
        loopProgressive = false
        loopRate = 1.0
        isPlaying = false
        progress = 0
        duration = 0
    }
}

/// Schlagzeug-Groove statt Klick: BD auf 1 & 3, SD auf 2 & 4, Hihat auf 8teln
/// (betont auf den BD/SD-Schlägen). Läuft im Songtempo (4/4).
@MainActor
final class Metronome: ObservableObject {
    @Published var isRunning = false
    @Published var eighth = 0          // Position im Takt (0…7)
    var bpm: Int = 120

    private let audio = AudioEngine()
    private var timer: Timer?

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard bpm > 0 else { return }
        stop()
        isRunning = true
        eighth = 0
        playSlot(0)
        let interval = (60.0 / Double(bpm)) / 2.0   // Achtelnoten
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.eighth = (self.eighth + 1) % 8
                self.playSlot(self.eighth)
            }
        }
    }

    /// Ein Achtel-Slot des Grundrhythmus.
    private func playSlot(_ e: Int) {
        let onDownbeat = (e % 2 == 0)        // Slots 0,2,4,6 = die Viertel
        audio.playHihat(accent: onDownbeat)  // Hihat 8tel, betont auf BD/SD
        if e == 0 || e == 4 { audio.playKick() }   // BD auf 1 & 3
        if e == 2 || e == 6 { audio.playSnare() }  // SD auf 2 & 4
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
}
