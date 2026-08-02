import SwiftUI
import Combine
import Foundation

/// Wie das Tempo beim Üben von Geschwindigkeitsstellen erhöht wird.
enum SpeedMode: String, CaseIterable, Identifiable {
    case manual         // per -/+ Buttons
    case autoTime       // pro Loop-Durchlauf automatisch schneller
    case autoPrecision  // schneller erst nach sauber gespielten Durchläufen

    var id: String { rawValue }
    var label: String {
        switch self {
        case .manual:        return "Manuell"
        case .autoTime:      return "Auto · Zeit"
        case .autoPrecision: return "Auto · Präzision"
        }
    }
}

/// Geteilte Steuerung für Speed-Loops: Einzähler, Tempo-Modi, -/+ und – im
/// Präzisionsmodus – eine **transparente** Timing-Analyse jedes Anschlags.
/// Wird sowohl im Übungskapitel als auch in der Song-Übung eingesetzt.
@MainActor
final class SpeedTrainer: ObservableObject {
    @Published var mode: SpeedMode = .manual
    @Published var countInBeat = 0          // 0 = kein Einzähler, 1…4 = laufend
    @Published var listening = false
    @Published var feedback: [OnsetFeedback] = []   // letzte Durchlauf-Analyse
    @Published var tightness: Double?               // 0…1 (1 = perfekt)
    @Published var verdict: String?                 // Klartext, was bemängelt wird
    @Published var passCount = 0                     // ausgewertete Durchläufe

    /// Ein erkannter Anschlag samt Abweichung vom (selbst-ermittelten) Raster.
    struct OnsetFeedback: Identifiable {
        let id: Int
        let deviation: Double   // Anteil eines 16tels: − = zu früh, + = zu spät (−0.5…+0.5)
        let ms: Double          // signierte Abweichung in Millisekunden
        var tight: Bool { abs(deviation) < 0.15 }
    }

    let startRate: Float = 0.6   // Anfangstempo der Speed-Übung

    private let audio = AudioEngine()
    private let listener = ListeningEngine()
    private weak var player: SongPlayer?
    private var bpm = 120
    private var onsetTimes: [Double] = []
    private var cleanPasses = 0

    func configure(player: SongPlayer, bpm: Int) {
        self.player = player
        self.bpm = max(1, bpm)
    }

    var tempoPercent: Int { Int(((player?.loopRate ?? 1) * 100).rounded()) }

    /// Vier Klicks im Start-Tempo als Einzähler (vor dem Loop-Start aufrufen).
    func countIn() async {
        guard bpm > 0 else { return }
        let interval = (60.0 / Double(bpm)) / Double(startRate)
        for beat in 1...4 {
            countInBeat = beat
            audio.playMetronomeClick(accent: beat == 1)
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        countInBeat = 0
    }

    /// Nach dem Start des Loops aufrufen: hängt die Auswertung an jeden Durchlauf.
    func loopStarted() {
        cleanPasses = 0
        passCount = 0
        feedback = []
        tightness = nil
        verdict = nil
        onsetTimes.removeAll()
        player?.onLoopRestart = { [weak self] in self?.evaluatePass() }
        if mode == .autoPrecision { startListening() } else { stopListening() }
    }

    func stop() {
        stopListening()
        player?.onLoopRestart = nil
    }

    func setMode(_ m: SpeedMode) {
        mode = m
        cleanPasses = 0
        guard let player, player.isLooping else { return }
        player.setProgressive(m == .autoTime)
        if m == .autoPrecision { startListening() } else { stopListening() }
    }

    func nudge(_ delta: Float) { player?.nudgeRate(by: delta) }

    // MARK: - Präzisions-Messung

    private func startListening() {
        onsetTimes.removeAll()
        listener.onOnset = { [weak self] t, _ in
            Task { @MainActor in self?.onsetTimes.append(t) }
        }
        listener.start { [weak self] ok in
            Task { @MainActor in self?.listening = ok }
        }
    }

    private func stopListening() {
        listener.onOnset = nil
        listener.stop()
        listening = false
    }

    /// Am Ende jedes Loop-Durchlaufs: Timing der Anschläge relativ zu einem
    /// selbst-ermittelten 16tel-Raster (Phase per zirkulärem Mittel). So sieht
    /// man pro Anschlag, ob und wie stark er zu früh/zu spät war.
    private func evaluatePass() {
        guard mode == .autoPrecision else { onsetTimes.removeAll(); return }
        let onsets = onsetTimes
        onsetTimes.removeAll()
        guard let player, bpm > 0, onsets.count >= 4 else {
            feedback = []; tightness = nil; verdict = nil; cleanPasses = 0
            return
        }
        let g = (60.0 / Double(bpm)) / Double(player.loopRate) / 4.0   // 16tel in Sekunden

        // Phase (Raster-Ursprung) als zirkuläres Mittel der Rest-Positionen.
        var sx = 0.0, sy = 0.0
        for t in onsets {
            let a = 2 * Double.pi * (t.truncatingRemainder(dividingBy: g) / g)
            sx += cos(a); sy += sin(a)
        }
        let phase = atan2(sy, sx) / (2 * Double.pi) * g

        var fb: [OnsetFeedback] = []
        var devAbsSum = 0.0
        for (i, t) in onsets.enumerated() {
            let k = ((t - phase) / g).rounded()
            var dev = t - (phase + k * g)          // in [−g/2, g/2]
            if dev > g / 2 { dev -= g }
            if dev < -g / 2 { dev += g }
            devAbsSum += abs(dev)
            fb.append(OnsetFeedback(id: i, deviation: dev / g, ms: dev * 1000))
        }
        feedback = fb
        passCount += 1

        let meanRel = devAbsSum / Double(onsets.count) / g   // 0…0.5
        let tight = max(0, 1 - meanRel / 0.5)
        tightness = tight

        let early = fb.filter { $0.deviation < -0.15 }.count
        let late  = fb.filter { $0.deviation >  0.15 }.count
        if early == 0 && late == 0 {
            verdict = "sauber im Raster"
        } else if early > late {
            verdict = "\(early)× zu früh (gehetzt)" + (late > 0 ? ", \(late)× zu spät" : "")
        } else if late > early {
            verdict = "\(late)× zu spät (geschleppt)" + (early > 0 ? ", \(early)× zu früh" : "")
        } else {
            verdict = "unruhig – \(early)× zu früh, \(late)× zu spät"
        }

        // Auto-Erhöhung nach zwei sauberen Durchläufen.
        if tight >= 0.8 {
            cleanPasses += 1
            if cleanPasses >= 2 { cleanPasses = 0; player.nudgeRate(by: 0.05) }
        } else {
            cleanPasses = 0
        }
    }
}

// MARK: - View

/// Kompakte Tempo-/Präzisions-Steuerung. In beiden Übungen identisch.
struct SpeedTrainerBar: View {
    @ObservedObject var trainer: SpeedTrainer
    let isLooping: Bool

    var body: some View {
        VStack(spacing: 10) {
            if trainer.countInBeat > 0 {
                Label("Einzähler … \(trainer.countInBeat)", systemImage: "metronome")
                    .font(.title3).fontWeight(.bold).foregroundColor(.orange)
            }

            Picker("Tempo-Modus", selection: Binding(
                get: { trainer.mode },
                set: { trainer.setMode($0) }
            )) {
                ForEach(SpeedMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 24) {
                Button { trainer.nudge(-0.05) } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 32))
                }
                .disabled(!isLooping)
                Text("\(trainer.tempoPercent) %")
                    .font(.title2).fontWeight(.semibold).monospacedDigit()
                    .frame(minWidth: 78)
                Button { trainer.nudge(0.05) } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 32))
                }
                .disabled(!isLooping)
            }

            if trainer.mode == .autoPrecision {
                precisionSection
            }
        }
    }

    private var precisionSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: trainer.listening ? "waveform" : "waveform.slash")
                    .foregroundColor(trainer.listening ? .green : .secondary)
                if let t = trainer.tightness {
                    Text("Präzision \(Int(t * 100)) %")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(t >= 0.8 ? .green : (t >= 0.6 ? .orange : .red))
                    if let v = trainer.verdict {
                        Text("· \(v)").font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    Text(trainer.listening ? "Mitspielen (USB-DI) – Analyse pro Durchlauf"
                                           : "Kein Eingang – Bass übers Interface anschließen")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            TimingMeter(feedback: trainer.feedback)
                .frame(height: 34)

            HStack {
                Text("← zu früh").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("Raster").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("zu spät →").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

/// Visualisiert die Abweichungen eines Durchlaufs: Mittellinie = exakt im
/// Raster, grünes Band = Toleranz. Jeder Punkt ein Anschlag, links = zu früh,
/// rechts = zu spät; grün/orange/rot je nach Größe der Abweichung.
struct TimingMeter: View {
    let feedback: [SpeedTrainer.OnsetFeedback]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let mid = w / 2
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(.secondarySystemBackground))
                // Toleranzband ±0.15 eines 16tels (von −0.5…+0.5 → 30 % der Breite).
                Rectangle().fill(Color.green.opacity(0.18))
                    .frame(width: w * 0.30)
                Rectangle().fill(Color.secondary.opacity(0.6)).frame(width: 1) // Raster-Mitte
                ForEach(feedback) { f in
                    Circle().fill(color(for: f))
                        .frame(width: 9, height: 9)
                        .position(x: mid + CGFloat(clamp(f.deviation) * 2) * (mid * 0.92),
                                  y: h / 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func clamp(_ d: Double) -> Double { max(-0.5, min(0.5, d)) }

    private func color(for f: SpeedTrainer.OnsetFeedback) -> Color {
        let a = abs(f.deviation)
        if a < 0.15 { return .green }
        if a < 0.30 { return .orange }
        return .red
    }
}
