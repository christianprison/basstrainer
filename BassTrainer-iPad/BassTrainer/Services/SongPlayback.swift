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
    /// Wiedergabetempo der normalen (nicht geloopten) Wiedergabe. 1.0 = Normal.
    @Published private(set) var baseRate: Float = 1.0

    /// Wird bei jedem Loop-Neustart (Sprung ans Loop-Ende → Anfang) aufgerufen.
    var onLoopRestart: (@MainActor () -> Void)?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var currentURL: URL?
    private var loop: (start: Double, end: Double)?
    private var loopProgressive = false
    // Zwei vorgepufferte Loop-Player für nahtlosen Rücksprung mit Crossfade.
    private var loopA: AVPlayer?
    private var loopB: AVPlayer?
    private var loopObsA: Any?
    private var loopObsB: Any?
    private var loopActiveIsA = true
    private var loopFadeTimer: Timer?
    private var loopSwapping = false
    private let crossfadeSeconds = 0.18
    private let minLoopRate: Float = 0.6
    private let rateStep: Float = 0.1
    // Grenzen für die manuelle Tempo-Steuerung (Speed-Übung).
    private let manualMin: Float = 0.4
    let manualMax: Float = 1.5

    private var activeLoop: AVPlayer? { loopActiveIsA ? loopA : loopB }

    /// Lädt einen neuen Track (oder leert den Player, wenn kein Pfad vorhanden).
    func load(path: String?) {
        stop()
        guard let path, let url = SupabaseConfig.publicAudioURL(for: path) else {
            hasTrack = false
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        currentURL = url
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
                // Loop-Rücksprung läuft über einen präzisen Boundary-Observer
                // (kein Preroll/Verzug); hier nur Fortschritt/Dauer aktualisieren.
                self.progress = time.seconds
                if let d = self.player?.currentItem?.duration.seconds, d.isFinite {
                    self.duration = d
                }
            }
        }
    }

    func toggle() {
        if loop != nil {
            if isPlaying { activeLoop?.pause(); isPlaying = false }
            else { activeLoop?.rate = loopRate; isPlaying = true }
            return
        }
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.rate = baseRate
            isPlaying = true
        }
    }

    /// Setzt das Wiedergabetempo der normalen Wiedergabe (Playback-Übung).
    func setBaseRate(_ r: Float) {
        baseRate = min(manualMax, max(0.4, (r * 20).rounded() / 20))
        if isPlaying && loop == nil { player?.rate = baseRate }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Spielt die markierte Stelle als Schleife. `progressive` = langsam → schneller.
    /// `startRate` überschreibt das Anfangstempo (für die manuelle Speed-Übung).
    /// Rücksprung über zwei vorgepufferte Player mit kurzem Crossfade – kein
    /// Preroll, keine Lücke, der Beat bleibt erhalten.
    func playLoop(start: Double, end: Double, progressive: Bool, startRate: Float? = nil) {
        guard let url = currentURL, end > start else { return }
        loop = (start, end)
        loopProgressive = progressive
        loopRate = startRate.map(clampRate) ?? (progressive ? minLoopRate : 1.0)
        player?.pause()                 // Hauptplayer ruht während des Loops
        teardownLoopPlayers()
        let a = makeLoopPlayer(url, start: start)
        let b = makeLoopPlayer(url, start: start)   // Standby, schon auf loop.start gepuffert
        loopA = a; loopB = b; loopActiveIsA = true
        a.volume = 1; b.volume = 0
        loopObsA = addLoopObserver(a, isA: true)
        loopObsB = addLoopObserver(b, isA: false)
        a.rate = loopRate
        progress = start
        isPlaying = true
    }

    private func makeLoopPlayer(_ url: URL, start: Double) -> AVPlayer {
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = false
        p.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        return p
    }

    private func addLoopObserver(_ p: AVPlayer, isA: Bool) -> Any {
        p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.02, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let loop = self.loop, isA == self.loopActiveIsA else { return }
                self.progress = time.seconds
                if let d = self.activeLoop?.currentItem?.duration.seconds, d.isFinite { self.duration = d }
                if !self.loopSwapping, time.seconds >= loop.end { self.startLoopCrossfade() }
            }
        }
    }

    /// Am Loop-Ende: Standby-Player (steht auf loop.start) auf dem Beat starten,
    /// per Crossfade übernehmen, alten Player als nächsten Standby vorbereiten.
    private func startLoopCrossfade() {
        guard let loop, !loopSwapping else { return }
        loopSwapping = true
        if loopProgressive { loopRate = min(1.0, loopRate + rateStep) }
        let outgoing = activeLoop
        loopActiveIsA.toggle()
        let incoming = activeLoop        // war Standby, exakt auf loop.start
        incoming?.volume = 0
        incoming?.rate = loopRate        // Wiedergabe ab loop.start – ohne Preroll
        progress = loop.start
        onLoopRestart?()

        loopFadeTimer?.invalidate()
        let steps = 12
        let interval = crossfadeSeconds / Double(steps)
        var i = 0
        loopFadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                i += 1
                let x = Float(i) / Float(steps)
                outgoing?.volume = 1 - x
                incoming?.volume = x
                if i >= steps {
                    t.invalidate(); self.loopFadeTimer = nil
                    outgoing?.pause(); outgoing?.volume = 0
                    outgoing?.seek(to: CMTime(seconds: loop.start, preferredTimescale: 600))
                    self.loopSwapping = false
                }
            }
        }
    }

    private func teardownLoopPlayers() {
        loopFadeTimer?.invalidate(); loopFadeTimer = nil
        if let loopObsA { loopA?.removeTimeObserver(loopObsA) }; loopObsA = nil
        if let loopObsB { loopB?.removeTimeObserver(loopObsB) }; loopObsB = nil
        loopA?.pause(); loopA = nil
        loopB?.pause(); loopB = nil
        loopSwapping = false
        loopActiveIsA = true
    }

    /// Schaltet die zeitgesteuerte Auto-Beschleunigung am laufenden Loop um.
    func setProgressive(_ on: Bool) { loopProgressive = on }

    /// Ändert das Loop-Tempo relativ (z. B. ±0.05) und wendet es sofort an.
    func nudgeRate(by delta: Float) { setLoopRate(loopRate + delta) }

    /// Setzt das Loop-Tempo (auf 5-%-Schritte gerundet, geklemmt).
    func setLoopRate(_ r: Float) {
        loopRate = clampRate(r)
        if loop != nil && isPlaying { activeLoop?.rate = loopRate }
    }

    private func clampRate(_ r: Float) -> Float {
        let stepped = (r * 20).rounded() / 20          // 5-%-Raster
        return min(manualMax, max(manualMin, stepped))
    }

    /// Beendet den Loop (normale Wiedergabe läuft am Hauptplayer weiter).
    func clearLoop() {
        let resumeAt = progress
        teardownLoopPlayers()
        loop = nil
        loopProgressive = false
        loopRate = 1.0
        if let player {
            player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
            if isPlaying { player.rate = baseRate }
        }
    }

    var isLooping: Bool { loop != nil }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        progress = seconds
    }

    /// Relativ vor-/zurückspulen (Sekunden), auf 0…Dauer geklemmt.
    func seekRelative(_ delta: Double) {
        let upper = duration > 0 ? duration : .greatestFiniteMagnitude
        seek(to: max(0, min(upper, progress + delta)))
    }

    func stop() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        teardownLoopPlayers()
        player = nil
        currentURL = nil
        loop = nil
        loopProgressive = false
        loopRate = 1.0
        baseRate = 1.0
        isPlaying = false
        progress = 0
        duration = 0
        onLoopRestart = nil
    }
}

/// Schlagzeug-Groove statt Klick. Spielt den pro Song hinterlegten
/// Grundrhythmus (`song_detail_lighting.detail->grundrhythmus`): BD-/SD-Schläge
/// an frei definierten Positionen im 4/4-Takt (in Viertel-Einheiten:
/// 0.0 = Zählzeit 1, 1.0 = 2, 2.0 = 3, 3.0 = 4, Nachkommastellen = Unterteilung).
/// Dazu eine durchgehende Hihat auf 8teln (unabhängig vom Grundrhythmus,
/// betont auf den Viertel-Zählzeiten).
/// Ohne Muster (oder BD+SD leer): Standard-Backbeat kick[0,2] snare[1,3].
@MainActor
final class Metronome: ObservableObject {
    @Published var isRunning = false
    var bpm: Int = 120

    /// Pro Song geladenes Muster (Viertel-Positionen). nil ⇒ Standard-Backbeat.
    var pattern: (kick: [Double], snare: [Double])?

    private let audio = AudioEngine()
    private var player: AVAudioPlayer?

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard bpm > 0 else { return }
        stop()
        let samples = renderBar()
        guard !samples.isEmpty,
              let p = audio.makeLoopingPlayer(samples: samples, sampleRate: audio.grooveSampleRate)
        else { return }
        // Wiedergabe-Session sicherstellen, damit der Loop hörbar ist.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = p
        p.play()
        isRunning = true
    }

    func stop() {
        player?.stop()
        player = nil
        isRunning = false
    }

    /// Übernimmt eine geänderte `bpm` live (re-rendert den Loop, falls aktiv).
    func reload() { if isRunning { start() } }

    // MARK: - Muster → 16tel-Raster

    /// Rundet auf das nächste 16tel (Viertel/4), um Duplikate zusammenzufassen.
    private func round16(_ x: Double) -> Double { (x * 4).rounded() / 4 }

    /// Liefert je 16tel-Slot (0…15) die Schläge: Kick, Snare, Hihat, Hihat-Akzent.
    private func slotHits() -> [(kick: Bool, snare: Bool, hihat: Bool, accent: Bool)] {
        let p = pattern ?? (kick: [0, 2], snare: [1, 3])
        var kick = Set(p.kick.map(round16))
        var snare = Set(p.snare.map(round16))
        if kick.isEmpty && snare.isEmpty {        // beide leer ⇒ Standard-Backbeat
            kick = [0, 2]; snare = [1, 3]
        }
        // 16 Slots à ein 16tel. Slot s liegt auf Viertel-Position s/4.
        return (0..<16).map { s in
            let beat = Double(s) / 4.0
            let hasKick = kick.contains(beat)
            let hasSnare = snare.contains(beat)
            // Hihat durchgehend auf 8teln (gerade Slots), unabhängig vom Muster,
            // betont auf den Viertel-Zählzeiten (Slot 0,4,8,12) als gerader Puls.
            let hasHihat = (s % 2 == 0)
            let accent = (s % 4 == 0)
            return (hasKick, hasSnare, hasHihat, accent)
        }
    }

    // MARK: - Rendering: ganzer Takt in einen Loop-Puffer

    /// Rendert einen kompletten 4/4-Takt sample-genau: jeder Schlag sitzt exakt
    /// auf seinem 16tel-Sample-Offset. Der Puffer wird per Hardware-Loop nahtlos
    /// wiederholt – kein Scheduling-Jitter, kein Drift.
    private func renderBar() -> [Float] {
        let sr = audio.grooveSampleRate
        let secPerBeat = 60.0 / Double(bpm)
        let barFrames = Int((secPerBeat * 4 * sr).rounded())
        guard barFrames > 0 else { return [] }

        var buf = [Float](repeating: 0, count: barFrames)
        let kick = audio.kickSamples()
        let snare = audio.snareSamples()
        let hhAccent = audio.hihatSamples(accent: true)
        let hhNormal = audio.hihatSamples(accent: false)
        let gain: Float = 0.7   // Headroom gegen Clipping bei gleichzeitigen Schlägen

        for (slot, hit) in slotHits().enumerated() {
            let start = Int((Double(slot) / 4.0 * secPerBeat * sr).rounded())
            if hit.kick { mix(&buf, kick, at: start, gain: gain) }
            if hit.snare { mix(&buf, snare, at: start, gain: gain) }
            if hit.hihat { mix(&buf, hit.accent ? hhAccent : hhNormal, at: start, gain: gain) }
        }
        return buf
    }

    /// Mischt `src` ab `start` additiv in `buf`; der Tail wickelt sich nahtlos
    /// über die Taktgrenze in den Loop-Anfang.
    private func mix(_ buf: inout [Float], _ src: [Float], at start: Int, gain: Float) {
        let n = buf.count
        guard n > 0 else { return }
        for i in 0..<src.count {
            buf[(start + i) % n] += src[i] * gain
        }
    }
}
