import Foundation
import AVFoundation
import QuartzCore

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

/// Schlagzeug-Groove statt Klick. Spielt den pro Song hinterlegten
/// Grundrhythmus (`song_detail_lighting.detail->grundrhythmus`): BD-/SD-Schläge
/// an frei definierten Positionen im 4/4-Takt (in Viertel-Einheiten:
/// 0.0 = Zählzeit 1, 1.0 = 2, 2.0 = 3, 3.0 = 4, Nachkommastellen = Unterteilung).
/// Dazu eine Hihat auf 8teln, betont auf den BD/SD-Positionen.
/// Ohne Muster (oder BD+SD leer): Standard-Backbeat kick[0,2] snare[1,3].
@MainActor
final class Metronome: ObservableObject {
    @Published var isRunning = false
    @Published var eighth = 0          // Position im Takt (0…7), nur für die UI-Anzeige
    var bpm: Int = 120

    /// Pro Song geladenes Muster (Viertel-Positionen). nil ⇒ Standard-Backbeat.
    var pattern: (kick: [Double], snare: [Double])?

    private let audio = AudioEngine()
    private var runToken = 0

    /// Ein einzelner Schlag innerhalb des Takts.
    private struct DrumEvent {
        let beat: Double         // Position in Vierteln (0…<4)
        let kick: Bool
        let snare: Bool
        let hihat: Bool
        let hihatAccent: Bool
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard bpm > 0 else { return }
        stop()
        isRunning = true
        runToken &+= 1
        scheduleBar(token: runToken, startHost: CACurrentMediaTime())
    }

    func stop() {
        runToken &+= 1
        isRunning = false
        eighth = 0
    }

    // MARK: - Muster → Events

    /// Rundet auf das nächste 16tel (Viertel/4), um Duplikate zusammenzufassen.
    private func round16(_ x: Double) -> Double { (x * 4).rounded() / 4 }

    /// Baut die sortierten Schlag-Events für einen Takt aus dem Muster.
    private func buildEvents() -> [DrumEvent] {
        let p = pattern ?? (kick: [0, 2], snare: [1, 3])
        var kick = Set(p.kick.map(round16))
        var snare = Set(p.snare.map(round16))
        // Beide leer ⇒ Standard-Backbeat.
        if kick.isEmpty && snare.isEmpty {
            kick = [0, 2]; snare = [1, 3]
        }
        // Nur Positionen innerhalb eines 4/4-Takts.
        kick = kick.filter { $0 >= 0 && $0 < 4 }
        snare = snare.filter { $0 >= 0 && $0 < 4 }

        // Hihat auf allen 8teln (0.0, 0.5, 1.0 … 3.5).
        let hihatBeats = Set((0..<8).map { Double($0) * 0.5 })

        let allBeats = kick.union(snare).union(hihatBeats).sorted()
        return allBeats.map { beat in
            let hasKick = kick.contains(beat)
            let hasSnare = snare.contains(beat)
            let hasHihat = hihatBeats.contains(beat)
            return DrumEvent(
                beat: beat,
                kick: hasKick,
                snare: hasSnare,
                hihat: hasHihat,
                hihatAccent: hasKick || hasSnare   // Hihat betont auf BD/SD
            )
        }
    }

    // MARK: - Scheduling

    /// Plant einen kompletten Takt und hängt am Ende den nächsten an.
    private func scheduleBar(token: Int, startHost: CFTimeInterval) {
        guard token == runToken else { return }
        let secPerBeat = 60.0 / Double(bpm)     // eine Viertel
        let barLength = secPerBeat * 4
        let events = buildEvents()

        for ev in events {
            let at = startHost + ev.beat * secPerBeat
            schedule(at: at, token: token) { [weak self] in
                guard let self, token == self.runToken else { return }
                if ev.kick { self.audio.playKick() }
                if ev.snare { self.audio.playSnare() }
                if ev.hihat { self.audio.playHihat(accent: ev.hihatAccent) }
                self.eighth = Int((ev.beat * 2).rounded()) % 8
            }
        }

        // Nächsten Takt exakt am Taktende starten (kein Drift durch Timer-Jitter).
        let nextStart = startHost + barLength
        schedule(at: nextStart, token: token) { [weak self] in
            guard let self, token == self.runToken else { return }
            self.scheduleBar(token: token, startHost: nextStart)
        }
    }

    /// Führt `action` zur absoluten Host-Zeit `at` auf dem Main-Thread aus.
    private func schedule(at host: CFTimeInterval, token: Int,
                          _ action: @escaping @MainActor () -> Void) {
        let delay = max(0, host - CACurrentMediaTime())
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                guard token == self.runToken else { return }
                action()
            }
        }
    }
}
