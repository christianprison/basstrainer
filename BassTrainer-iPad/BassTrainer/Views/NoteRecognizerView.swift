import SwiftUI
import Combine

/// Noten-Erkennung, die ausschließlich aus deinem Feedback lernt: Ton spielen →
/// der Trainer schlägt die Lagen der Tonhöhe vor (nach gelerntem Fingerabdruck)
/// → du wählst; jede Auswahl verfeinert Mittelwert + Streuung deiner Merkmale.
struct NoteRecognizerView: View {
    @StateObject private var vm = NoteRecognizerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            header
            techniqueRow
            vuMeter
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            if let c = vm.confirmed {
                Label(c, systemImage: "checkmark.circle.fill").font(.headline).foregroundColor(.green)
            }
            trainingRow
            controls
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Noten-Erkennung").font(.headline)
                Text("Selbstlernend aus deinem Feedback").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button { vm.stop(); dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
            }
        }
    }

    private var techniqueRow: some View {
        HStack(spacing: 10) {
            Text("Technik").font(.caption).foregroundColor(.secondary)
            Picker("Technik", selection: $vm.technique) {
                ForEach(PlayTechnique.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            Spacer()
        }
    }

    private var vuMeter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Eingangspegel – Gain so justieren, dass laute Töne knapp unter Rot bleiben")
                .font(.caption2).foregroundColor(.secondary)
            GeometryReader { geo in
                let lvl = CGFloat(min(1, max(0, vm.level)))
                let color: Color = vm.level < 0.7 ? .green : (vm.level < 0.9 ? .yellow : .red)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5).fill(Color(.tertiarySystemFill))
                    RoundedRectangle(cornerRadius: 5).fill(color).frame(width: geo.size.width * lvl)
                    Rectangle().fill(Color.red.opacity(0.6)).frame(width: 2)
                        .position(x: geo.size.width * 0.9, y: geo.size.height / 2)
                }
            }
            .frame(height: 16)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .denied:
            VStack(spacing: 12) {
                Image(systemName: "mic.slash.fill").font(.system(size: 44)).foregroundColor(.secondary)
                Text("Mikrofon-Zugriff verweigert").font(.headline)
            }
        case .choose:
            candidateList
        default:
            VStack(spacing: 10) {
                Image(systemName: "guitars").font(.system(size: 48)).foregroundColor(.accentColor)
                Text("Spiele einen Ton").font(.title2).bold()
                Text("Der Trainer zeigt die Lagen der Tonhöhe – nach dem, was er von dir gelernt hat. Wähle die richtige, um ihn zu trainieren.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private var candidateList: some View {
        VStack(spacing: 10) {
            Text("Erkannt: \(vm.capturedNote) – welche Position war es?")
                .font(.subheadline).foregroundColor(.secondary)
            ForEach(vm.candidates) { c in
                Button { vm.choose(c) } label: { candidateRow(c) }.buttonStyle(.plain)
            }
            Button { vm.none() } label: {
                Label("Nichts davon", systemImage: "xmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).tint(.red)
        }
    }

    private func candidateRow(_ c: ScoredCandidate) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(BassIntro.stringName[c.string] ?? "?")-Saite · Bund \(c.fret)").font(.headline)
                Text(c.samples > 0 ? "\(c.noteName) · \(c.samples)× gelernt" : c.noteName)
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int((c.probability * 100).rounded())) %").font(.subheadline).monospacedDigit()
                ProgressView(value: c.probability, total: 1.0).frame(width: 120).tint(.accentColor)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private var trainingRow: some View {
        HStack(spacing: 12) {
            Text("Gelernt: \(vm.totalSamples) Beispiele").font(.caption).foregroundColor(.secondary)
            if let s = vm.syncStatus { Text("· \(s)").font(.caption2).foregroundColor(.secondary) }
            Spacer()
            Button { vm.save() } label: { Label("Speichern", systemImage: "icloud.and.arrow.up") }
                .font(.caption)
        }
    }

    private var controls: some View {
        Button { vm.toggle() } label: {
            Label(vm.isListening ? "Pause" : "Weiter", systemImage: vm.isListening ? "pause.fill" : "mic.fill")
                .font(.headline).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .tint(vm.isListening ? .orange : .accentColor)
    }
}

// MARK: - ViewModel

@MainActor
final class NoteRecognizerViewModel: ObservableObject {
    enum State { case idle, listening, choose, denied }

    @Published var state: State = .idle
    @Published var candidates: [ScoredCandidate] = []
    @Published var capturedNote: String = ""
    @Published var confirmed: String?
    @Published var isListening = false
    @Published var level: Float = 0
    @Published var technique: PlayTechnique = .fingered

    private let tuner = TunerEngine()
    private let audio = AudioEngine()
    private let matcher = NoteMatcher()
    private var cancellables = Set<AnyCancellable>()
    private var didLoad = false

    var totalSamples: Int { matcher.totalSamples }
    var syncStatus: String? { matcher.syncStatus }

    init() {
        tuner.$level.receive(on: DispatchQueue.main).assign(to: &$level)
        matcher.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        tuner.onNoteHeld = { [weak self] seg, sr, f0 in
            Task { @MainActor in self?.handle(segment: seg, sampleRate: sr, f0: f0) }
        }
        tuner.start()
        isListening = true
        if state == .idle { state = .listening }
        if !didLoad { didLoad = true; Task { await matcher.loadFromCloud() } }
    }

    func stop() { tuner.stop(); isListening = false }
    func toggle() { if isListening { stop() } else { start() } }
    func save() { Task { await matcher.saveToCloud() } }

    private func handle(segment: [Float], sampleRate: Double, f0: Double) {
        guard isListening else { return }
        capturedNote = BassIntro.noteName(forMidi: Int((69.0 + 12.0 * log2(f0 / 440.0)).rounded()))
        let (cands, _) = matcher.rank(segment: segment, sampleRate: sampleRate, f0: f0, technique: technique)
        candidates = cands
        state = cands.isEmpty ? .listening : .choose
    }

    func choose(_ c: ScoredCandidate) {
        matcher.confirm(posKey: c.key, technique: technique)   // lernen
        let map: [Int: BassString] = [1: .b, 2: .e, 3: .a, 4: .d, 5: .g]
        audio.playBassNote(position: FretPosition(string: map[c.string] ?? .e, fret: c.fret))
        confirmed = "\(BassIntro.stringName[c.string] ?? "?")-Saite, Bund \(c.fret) (\(c.noteName))"
        candidates = []
        state = .listening
    }

    func none() {
        candidates = []
        confirmed = nil
        state = .listening
    }
}

#Preview {
    NoteRecognizerView()
}
