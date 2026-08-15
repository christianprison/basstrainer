import SwiftUI
import QuartzCore

/// Ein erkanntes Tonsegment auf dem Zeitstrahl (Saite/Bund = Tonhöhe,
/// start…end = Tondauer).
struct NoteSegment: Identifiable {
    let id = UUID()
    let string: BassString
    let fret: Int
    let label: String
    let start: CFTimeInterval
    var end: CFTimeInterval
}

/// Baut aus dem Live-Pitch (TunerEngine.detected) einen fortlaufenden Verlauf
/// von Tonsegmenten für den scrollenden Tab-Zeitstrahl.
@MainActor
final class NoteTimelineModel: ObservableObject {
    let window: Double = 7            // sichtbare Sekunden

    private(set) var segments: [NoteSegment] = []
    private var current: NoteSegment?
    private var latest: DetectedNote?
    private var lastValidHost: CFTimeInterval = 0
    private var timer: Timer?
    private let grace = 0.14          // kurze Lücken überbrücken

    /// Alle aktuell sichtbaren Segmente (inkl. offenem).
    var visibleSegments: [NoteSegment] {
        if let c = current { return segments + [c] }
        return segments
    }

    /// Vom View bei jeder Erkennungsänderung gesetzt.
    func setDetected(_ d: DetectedNote?) { latest = d }

    func start() {
        stopTimer()
        segments.removeAll(); current = nil
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        stopTimer()
        if let c = current { segments.append(c); current = nil }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    private func tick() {
        let now = CACurrentMediaTime()
        if let d = latest, let pos = position(for: d) {
            lastValidHost = now
            if var c = current, c.string == pos.0, c.fret == pos.1 {
                c.end = now; current = c
            } else {
                if let c = current { segments.append(c) }
                current = NoteSegment(string: pos.0, fret: pos.1, label: d.label, start: now, end: now)
            }
        } else if var c = current {
            if now - lastValidHost > grace { segments.append(c); current = nil }
            else { c.end = now; current = c }
        }
        let cutoff = now - window - 1
        segments.removeAll { $0.end < cutoff }
    }

    /// Tonhöhe → beste (Saite, Bund) auf dem 5-Saiter (kleinster Bund ≥ 0).
    private func position(for d: DetectedNote) -> (BassString, Int)? {
        let midi = Int((69.0 + 12.0 * log2(d.frequency / 440.0)).rounded())
        var best: (BassString, Int)?
        for s in BassString.allCases {
            let openMidi = Int((69.0 + 12.0 * log2(s.openFrequency / 440.0)).rounded())
            let fret = midi - openMidi
            if fret >= 0 && fret <= 24, best == nil || fret < best!.1 {
                best = (s, fret)
            }
        }
        return best
    }
}

/// Einfaches Metronom mit variablem Tempo; liefert Startzeit + Beat-Intervall
/// für das Raster im Zeitstrahl.
@MainActor
final class TunerMetronome: ObservableObject {
    @Published var bpm: Double = 90
    @Published var isRunning = false
    private(set) var startHost: CFTimeInterval = 0

    private let audio = AudioEngine()
    private var timer: Timer?
    private var beatCount = 0

    var beatInterval: Double { 60.0 / max(30, bpm) }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        stop()
        startHost = CACurrentMediaTime()
        beatCount = 0
        isRunning = true
        audio.playMetronomeClick(accent: true)
        timer = Timer.scheduledTimer(withTimeInterval: beatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.click() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil; isRunning = false }
    func bpmChanged() { if isRunning { start() } }

    private func click() {
        beatCount += 1
        audio.playMetronomeClick(accent: beatCount % 4 == 0)
    }
}

/// Scrollender Bass-Tab-Zeitstrahl (5 Saiten). „Jetzt" ist rechts; Segmente
/// wandern nach links. Balkenlänge = Tondauer, Zahl = Bund.
struct TabTimelineView: View {
    @ObservedObject var model: NoteTimelineModel
    @ObservedObject var metro: TunerMetronome

    // Oben nach unten: G D A E B (wie im App-Griffbrett).
    private let strings: [BassString] = [.g, .d, .a, .e, .b]

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in draw(ctx, size) }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 1))
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let now = CACurrentMediaTime()
        let window = model.window
        let px = size.width / CGFloat(window)
        let rowH = size.height / CGFloat(strings.count)

        // Saitenlinien + Beschriftung.
        for (i, s) in strings.enumerated() {
            let y = rowH * (CGFloat(i) + 0.5)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(line, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            ctx.draw(Text(s.name).font(.caption2).foregroundColor(.secondary),
                     at: CGPoint(x: 12, y: y), anchor: .center)
        }

        // Beat-Raster.
        if metro.isRunning {
            let bi = metro.beatInterval
            var k = max(0, Int(((now - window - metro.startHost) / bi).rounded(.down)))
            while true {
                let t = metro.startHost + Double(k) * bi
                if t > now { break }
                let x = size.width - CGFloat(now - t) * px
                if x >= 0 {
                    let accent = k % 4 == 0
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(.secondary.opacity(accent ? 0.35 : 0.15)),
                               lineWidth: accent ? 1.5 : 1)
                }
                k += 1
            }
        }

        // Tonsegmente.
        for seg in model.visibleSegments {
            guard let row = strings.firstIndex(of: seg.string) else { continue }
            let y = rowH * (CGFloat(row) + 0.5)
            let xStart = size.width - CGFloat(now - seg.start) * px
            let xEnd = size.width - CGFloat(now - seg.end) * px
            let x0 = max(0, min(size.width, xStart))
            let x1 = max(0, min(size.width, xEnd))
            guard x1 > x0 - 0.5 else { continue }
            let h = rowH * 0.6
            let rect = CGRect(x: x0, y: y - h / 2, width: max(3, x1 - x0), height: h)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(.accentColor))
            if rect.width > 16 {
                ctx.draw(Text("\(seg.fret)").font(.caption2).bold().foregroundColor(.white),
                         at: CGPoint(x: rect.midX, y: y), anchor: .center)
            }
        }

        // „Jetzt"-Linie rechts.
        var nl = Path()
        nl.move(to: CGPoint(x: size.width - 1, y: 0))
        nl.addLine(to: CGPoint(x: size.width - 1, y: size.height))
        ctx.stroke(nl, with: .color(.red.opacity(0.7)), lineWidth: 2)
    }
}
