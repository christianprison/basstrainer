import SwiftUI

/// Finger-Warm-ups: Chromatic Crawl (1-2-3-4 pro Saite) und Spider (Finger-
/// Permutationen über Saitenpaare). Ein Ton pro Klick, dem Punkt auf dem
/// Griffbrett folgen; Finger 1–4 werden angezeigt.
struct WarmupView: View {
    @StateObject private var vm = WarmupViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            header
            HStack(spacing: 16) {
                Picker("Übung", selection: $vm.mode) {
                    ForEach(WarmupViewModel.Mode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 260)
                .onChange(of: vm.mode) { _, _ in vm.reset() }
                Stepper("Bund \(vm.startFret)", value: $vm.startFret, in: 1...12)
                    .onChange(of: vm.startFret) { _, _ in vm.reset() }
                    .fixedSize()
                Spacer()
            }
            headline
            ScrollView(.horizontal, showsIndicators: true) {
                let w: CGFloat = 1800
                FretboardView(
                    currentPosition: nil, isPlaying: false, levelColor: .accentColor,
                    markers: vm.patternPositions,
                    markerColor: Color(red: 0.20, green: 0.50, blue: 0.95),
                    rootMarkers: [vm.current],
                    rootColor: Color(red: 0.90, green: 0.20, blue: 0.55),
                    markerScale: 0.78
                )
                .frame(width: w, height: w * 332.0 / 4019.0)
            }
            transport
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .onDisappear { vm.stop() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { vm.stop(); dismiss() } label: {
                Label("Menü", systemImage: "chevron.left").font(.subheadline.weight(.semibold))
            }
            Spacer()
            Text("Warm-up").font(.headline)
            Spacer()
            Label("Menü", systemImage: "chevron.left").font(.subheadline.weight(.semibold)).opacity(0)
        }
    }

    private var headline: some View {
        VStack(spacing: 2) {
            Text("\(vm.current.string.name)-Saite · Bund \(vm.current.fret)")
                .font(.system(size: 34, weight: .bold, design: .rounded)).foregroundColor(.accentColor)
            Text("Finger \(vm.currentFinger)").font(.caption).foregroundColor(.secondary)
        }
    }

    private var transport: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "metronome").foregroundColor(.secondary)
                Slider(value: $vm.bpm, in: 40...160, step: 1) { editing in if !editing { vm.bpmChanged() } }
                Text("\(Int(vm.bpm)) BPM").font(.caption).monospacedDigit().frame(width: 70)
            }
            Button { vm.toggle() } label: {
                Image(systemName: vm.isRunning ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 52))
            }
            .buttonStyle(.plain).foregroundColor(.accentColor)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class WarmupViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case chromatic, spider
        var id: String { rawValue }
        var label: String { self == .chromatic ? "Chromatic Crawl" : "Spider" }
    }

    @Published var mode: Mode = .chromatic
    @Published var startFret = 1
    @Published var bpm: Double = 70
    @Published var isRunning = false
    @Published var stepIndex = 0

    private let audio = AudioEngine()
    private var timer: Timer?

    // Saiten von tief nach hoch.
    private let lowToHigh: [BassString] = [.b, .e, .a, .d, .g]

    /// Alle Positionen der aktuellen Übung (aufsteigend).
    var patternPositions: [FretPosition] {
        switch mode {
        case .chromatic:
            var res: [FretPosition] = []
            for s in lowToHigh {
                for f in startFret...(startFret + 3) { res.append(FretPosition(string: s, fret: f)) }
            }
            return res
        case .spider:
            // Über benachbarte Saitenpaare: lo f, hi f+1, lo f+2, hi f+3.
            var res: [FretPosition] = []
            for i in 0..<(lowToHigh.count - 1) {
                let lo = lowToHigh[i], hi = lowToHigh[i + 1]
                res.append(FretPosition(string: lo, fret: startFret))
                res.append(FretPosition(string: hi, fret: startFret + 1))
                res.append(FretPosition(string: lo, fret: startFret + 2))
                res.append(FretPosition(string: hi, fret: startFret + 3))
            }
            return res
        }
    }

    var current: FretPosition {
        let p = patternPositions
        return p.isEmpty ? FretPosition(string: .e, fret: startFret) : p[stepIndex % p.count]
    }

    /// Finger 1–4 = Bund − Startbund + 1.
    var currentFinger: Int { max(1, min(4, current.fret - startFret + 1)) }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        stop()
        isRunning = true
        audio.playMetronomeClick(accent: true)
        let step = 60.0 / max(40, bpm)
        timer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil; isRunning = false }
    func bpmChanged() { if isRunning { start() } }
    func reset() { stepIndex = 0 }

    private func advance() {
        let count = max(1, patternPositions.count)
        stepIndex = (stepIndex + 1) % count
        audio.playMetronomeClick(accent: stepIndex == 0)
    }
}

#Preview {
    WarmupView()
}
