import SwiftUI

/// Plektrum-Übung „Oktaven": Oktav-Pattern (Grundton + Oktave zwei Saiten höher,
/// +2 Bünde) zum Metronom-Klick, aufsteigend über den Hals — jede Lage zweimal
/// angeschlagen. Umschalter „Dead Notes" (gemutet üben) und optional progressiv
/// schneller.
struct PickOctavesView: View {
    @StateObject private var vm = PickOctavesViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            header
            optionsRow
            noteHeadline
            FretboardView(
                currentPosition: nil,
                isPlaying: false,
                levelColor: .accentColor,
                markers: vm.markers,
                markerColor: vm.deadNotes ? .gray : .accentColor
            )
            .aspectRatio(4019.0 / 332.0, contentMode: .fit)
            .padding(.vertical, 4)
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
            Text("Pick · Oktaven").font(.headline)
            Spacer()
            Label("Menü", systemImage: "chevron.left").font(.subheadline.weight(.semibold)).opacity(0)
        }
    }

    private var optionsRow: some View {
        HStack(spacing: 16) {
            Menu {
                ForEach(vm.lowStringChoices, id: \.self) { s in
                    Button("\(s.name)-Saite") { vm.lowString = s; vm.reset() }
                }
            } label: {
                labelChip(title: "Startsaite", value: "\(vm.lowString.name)")
            }
            Toggle(isOn: $vm.deadNotes) { Text("Dead Notes").font(.subheadline) }
                .toggleStyle(.button)
            Toggle(isOn: $vm.progressive) { Text("Progressiv").font(.subheadline) }
                .toggleStyle(.button)
            Spacer()
        }
    }

    private func labelChip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.headline).monospaced()
            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private var noteHeadline: some View {
        VStack(spacing: 2) {
            Text(vm.rootNoteName)
                .font(.system(size: 60, weight: .black, design: .rounded))
                .foregroundColor(vm.deadNotes ? .gray : .accentColor)
            Text(vm.deadNotes
                 ? "Oktave gemutet (Dead Notes) · Bund \(vm.rootFret) → \(vm.rootFret + 2)"
                 : "Oktave · Bund \(vm.rootFret) → \(vm.rootFret + 2)")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var transport: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "metronome").foregroundColor(.secondary)
                Slider(value: $vm.bpm, in: 40...160, step: 1) { editing in
                    if !editing { vm.bpmChanged() }
                }
                Text("\(Int(vm.bpm)) BPM").font(.caption).monospacedDigit().frame(width: 70)
            }
            Button { vm.toggle() } label: {
                Image(systemName: vm.isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
            }
            .buttonStyle(.plain).foregroundColor(.accentColor)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class PickOctavesViewModel: ObservableObject {
    @Published var lowString: BassString = .e
    @Published var deadNotes = false
    @Published var progressive = false
    @Published var bpm: Double = 70
    @Published var isRunning = false
    @Published var rootFret = 1

    private let audio = AudioEngine()
    private var timer: Timer?
    private var beatInPos = 0            // 0/1 → jede Lage zweimal anschlagen
    private let minFret = 1
    private let maxFret = 12
    private let hitsPerPosition = 2
    private let progStep: Double = 6     // BPM-Zuwachs pro kompletter Auf-Runde

    /// Nur Saiten, für die eine Oktave zwei Saiten höher existiert (B, E, A).
    var lowStringChoices: [BassString] { [.b, .e, .a] }

    private var octaveString: BassString? { BassString(rawValue: lowString.rawValue - 2) }

    var markers: [FretPosition] {
        let root = FretPosition(string: lowString, fret: rootFret)
        guard let os = octaveString else { return [root] }
        return [root, FretPosition(string: os, fret: rootFret + 2)]
    }

    var rootNoteName: String { FretPosition(string: lowString, fret: rootFret).note.rawValue }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        stop()
        isRunning = true
        beatInPos = 0
        click()
        let step = 60.0 / max(40, bpm)
        timer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        isRunning = false
    }

    func bpmChanged() { if isRunning { start() } }

    func reset() { rootFret = minFret; beatInPos = 0 }

    private func advance() {
        beatInPos += 1
        if beatInPos >= hitsPerPosition {
            beatInPos = 0
            rootFret += 1
            if rootFret > maxFret {
                rootFret = minFret
                if progressive { bpm = min(160, bpm + progStep); restartTimer() }
            }
        }
        click()
    }

    /// Tempo im laufenden Betrieb neu takten (für Progressiv).
    private func restartTimer() {
        timer?.invalidate()
        let step = 60.0 / max(40, bpm)
        timer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }

    private func click() {
        // Betonung auf dem ersten Anschlag einer Lage; bei Dead Notes leiser/unbetont.
        audio.playMetronomeClick(accent: !deadNotes && beatInPos == 0)
    }
}

#Preview {
    PickOctavesView()
}
