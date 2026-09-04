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
    private var boundaryObserver: Any?
    private var loop: (start: Double, end: Double)?
    private var loopProgressive = false
    private let minLoopRate: Float = 0.6
    private let rateStep: Float = 0.1
    // Grenzen für die manuelle Tempo-Steuerung (Speed-Übung).
    private let manualMin: Float = 0.4
    let manualMax: Float = 1.5

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
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.rate = (loop != nil) ? loopRate : baseRate
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
    func playLoop(start: Double, end: Double, progressive: Bool, startRate: Float? = nil) {
        guard let player, end > start else { return }
        loop = (start, end)
        loopProgressive = progressive
        if let startRate { loopRate = clampRate(startRate) }
        else { loopRate = progressive ? minLoopRate : 1.0 }
        seek(to: start)
        player.rate = loopRate
        isPlaying = true
        installLoopBoundary()
    }

    /// Präziser Rücksprung am Loop-Ende (feuert exakt beim Überschreiten von
    /// `loop.end`, ohne das ~100-ms-Raster des periodischen Observers).
    private func installLoopBoundary() {
        if let boundaryObserver { player?.removeTimeObserver(boundaryObserver); self.boundaryObserver = nil }
        guard let player, let loop else { return }
        let end = CMTime(seconds: loop.end, preferredTimescale: 600)
        boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: end)], queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let loop = self.loop, let player = self.player else { return }
                if self.loopProgressive { self.loopRate = min(1.0, self.loopRate + self.rateStep) }
                player.seek(to: CMTime(seconds: loop.start, preferredTimescale: 600))
                player.rate = self.loopRate
                self.progress = loop.start
                self.onLoopRestart?()
            }
        }
    }

    private func removeLoopBoundary() {
        if let boundaryObserver { player?.removeTimeObserver(boundaryObserver) }
        boundaryObserver = nil
    }

    /// Schaltet die zeitgesteuerte Auto-Beschleunigung am laufenden Loop um.
    func setProgressive(_ on: Bool) { loopProgressive = on }

    /// Ändert das Loop-Tempo relativ (z. B. ±0.05) und wendet es sofort an.
    func nudgeRate(by delta: Float) { setLoopRate(loopRate + delta) }

    /// Setzt das Loop-Tempo (auf 5-%-Schritte gerundet, geklemmt).
    func setLoopRate(_ r: Float) {
        loopRate = clampRate(r)
        if loop != nil && isPlaying { player?.rate = loopRate }
    }

    private func clampRate(_ r: Float) -> Float {
        let stepped = (r * 20).rounded() / 20          // 5-%-Raster
        return min(manualMax, max(manualMin, stepped))
    }

    /// Beendet den Loop (normale Wiedergabe läuft in Originaltempo weiter).
    func clearLoop() {
        removeLoopBoundary()
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
        removeLoopBoundary()
        player = nil
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
