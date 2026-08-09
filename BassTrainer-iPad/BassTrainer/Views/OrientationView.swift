import SwiftUI

/// „Orientierung" – Töne auf dem Hals finden (Übungen des Basslehrers):
///  • Reihe: Tonreihe in Quinten/Quarten über den ganzen Hals, vor-/rückwärts.
///  • Eine Saite: dieselbe Reihe nur auf einer Saite.
///  • Ton finden: einen Ton über alle Saiten hinweg zeigen.
/// Ein langsamer Metronom-Klick schaltet die Reihe Ton für Ton weiter.
struct OrientationView: View {
    @StateObject private var vm = OrientationViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            header
            modePicker
            optionsRow
            noteHeadline
            FretboardView(
                currentPosition: nil,
                isPlaying: false,
                levelColor: .accentColor,
                markers: vm.markers,
                markerColor: .accentColor
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

    // MARK: - Kopf

    private var header: some View {
        HStack(spacing: 12) {
            Button { vm.stop(); dismiss() } label: {
                Label("Menü", systemImage: "chevron.left").font(.subheadline.weight(.semibold))
            }
            Spacer()
            Text("Orientierung").font(.headline)
            Spacer()
            // Platzhalter für symmetrische Breite
            Label("Menü", systemImage: "chevron.left").font(.subheadline.weight(.semibold)).opacity(0)
        }
    }

    private var modePicker: some View {
        Picker("Modus", selection: $vm.mode) {
            ForEach(OrientationViewModel.Mode.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Optionen je Modus

    @ViewBuilder
    private var optionsRow: some View {
        HStack(spacing: 16) {
            switch vm.mode {
            case .row:
                intervalPicker
                startNoteMenu
                beatsMenu
            case .oneString:
                intervalPicker
                startNoteMenu
                stringMenu
                beatsMenu
            case .findNote:
                targetNoteMenu
            }
            Spacer()
        }
    }

    /// Wie viele Klicks pro Ton (Zeit zum Suchen + alle Positionen spielen).
    private var beatsMenu: some View {
        Menu {
            ForEach([2, 4, 8], id: \.self) { n in
                Button("\(n) Klicks/Ton") { vm.beatsPerNote = n }
            }
        } label: {
            labelChip(title: "Pro Ton", value: "\(vm.beatsPerNote)")
        }
    }

    private var intervalPicker: some View {
        Picker("Intervall", selection: $vm.interval) {
            ForEach(OrientationViewModel.Interval.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
        .onChange(of: vm.interval) { _, _ in vm.resetStep() }
    }

    private var startNoteMenu: some View {
        Menu {
            ForEach(NoteName.allNotes) { n in
                Button(n.rawValue) { vm.startNote = n; vm.resetStep() }
            }
        } label: {
            labelChip(title: "Start", value: vm.startNote.rawValue)
        }
    }

    private var stringMenu: some View {
        Menu {
            ForEach(BassString.allCases) { s in
                Button("\(s.name)-Saite") { vm.selectedString = s }
            }
        } label: {
            labelChip(title: "Saite", value: "\(vm.selectedString.name)")
        }
    }

    private var targetNoteMenu: some View {
        Menu {
            ForEach(NoteName.allNotes) { n in
                Button(n.rawValue) { vm.targetNote = n }
            }
        } label: {
            labelChip(title: "Ton", value: vm.targetNote.rawValue)
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

    // MARK: - Aktueller Ton

    private var noteHeadline: some View {
        VStack(spacing: 2) {
            Text(vm.currentNote.rawValue)
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundColor(.accentColor)
            if vm.mode != .findNote {
                Text("Schritt \(vm.stepIndex + 1)/12 · \(vm.interval.label) ab \(vm.startNote.rawValue)")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text("Alle Positionen von \(vm.targetNote.rawValue) auf dem Hals")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Transport (Tempo + Steuerung)

    private var transport: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "metronome").foregroundColor(.secondary)
                Slider(value: $vm.bpm, in: 30...100, step: 1) { editing in
                    if !editing { vm.bpmChanged() }
                }
                Text("\(Int(vm.bpm)) BPM").font(.caption).monospacedDigit().frame(width: 70)
            }
            HStack(spacing: 24) {
                if vm.mode != .findNote {
                    Button { vm.prev() } label: { Image(systemName: "backward.fill").font(.title3) }
                }
                Button { vm.toggle() } label: {
                    Image(systemName: vm.isRunning ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }
                .buttonStyle(.plain).foregroundColor(.accentColor)
                if vm.mode != .findNote {
                    Button { vm.next() } label: { Image(systemName: "forward.fill").font(.title3) }
                }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class OrientationViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case row, oneString, findNote
        var id: String { rawValue }
        var label: String {
            switch self {
            case .row:       return "Reihe"
            case .oneString: return "Eine Saite"
            case .findNote:  return "Ton finden"
            }
        }
    }
    enum Interval: String, CaseIterable, Identifiable {
        case fifths, fourths
        var id: String { rawValue }
        var label: String { self == .fifths ? "Quinten" : "Quarten" }
        var semitones: Int { self == .fifths ? 7 : 5 }
    }

    @Published var mode: Mode = .row
    @Published var interval: Interval = .fifths
    @Published var startNote: NoteName = .c
    @Published var selectedString: BassString = .b
    @Published var targetNote: NoteName = .c
    @Published var bpm: Double = 50
    @Published var isRunning = false
    @Published var stepIndex = 0
    /// Wie viele Klicks pro Ton (Zeit zum Suchen + alle Positionen spielen).
    @Published var beatsPerNote = 4

    private let audio = AudioEngine()
    private var timer: Timer?
    private var beatCount = 0
    private let maxFret = 12

    /// 12-Ton-Reihe im gewählten Intervall ab Startton.
    var sequence: [NoteName] {
        let start = NoteName.allNotes.firstIndex(of: startNote) ?? 0
        return (0..<12).map { NoteName.allNotes[(start + $0 * interval.semitones) % 12] }
    }

    var currentNote: NoteName {
        mode == .findNote ? targetNote : sequence[stepIndex % sequence.count]
    }

    /// Griffbrett-Marker je Modus.
    var markers: [FretPosition] {
        switch mode {
        case .row:       return positions(of: currentNote, strings: BassString.allCases, upTo: maxFret)
        case .oneString: return positions(of: currentNote, strings: [selectedString], upTo: maxFret)
        case .findNote:  return positions(of: targetNote, strings: BassString.allCases, upTo: maxFret)
        }
    }

    private func positions(of note: NoteName, strings: [BassString], upTo: Int) -> [FretPosition] {
        var res: [FretPosition] = []
        for s in strings {
            for f in 0...upTo where s.notePattern[f % 12] == note {
                res.append(FretPosition(string: s, fret: f))
            }
        }
        return res
    }

    // MARK: - Steuerung

    func toggle() { isRunning ? stop() : start() }

    func start() {
        stop()
        isRunning = true
        beatCount = 0
        click(accent: true)   // erster Klick des aktuellen Tons
        let step = 60.0 / max(30, bpm)
        timer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        isRunning = false
    }

    /// Tempo geändert: bei laufendem Klick neu takten.
    func bpmChanged() { if isRunning { start() } }

    private func advance() {
        if mode == .findNote { click(accent: false); return }
        beatCount += 1
        var noteChanged = false
        if beatCount >= max(1, beatsPerNote) {
            beatCount = 0
            stepIndex = (stepIndex + 1) % sequence.count
            noteChanged = true
        }
        click(accent: noteChanged)   // Betonung nur beim Ton-Wechsel
    }

    private func click(accent: Bool) {
        audio.playMetronomeClick(accent: accent)
    }

    func next() { if mode != .findNote { beatCount = 0; stepIndex = (stepIndex + 1) % 12 } }
    func prev() { if mode != .findNote { beatCount = 0; stepIndex = (stepIndex + 11) % 12 } }
    func resetStep() { beatCount = 0; stepIndex = 0 }
}

#Preview {
    OrientationView()
}
