import SwiftUI

/// Noten-Erkennung per Sample-Vergleich: Ton spielen → der Trainer schlägt die
/// wahrscheinlichsten Saiten/Bünde vor (+ „Nichts davon") → du wählst aus.
struct NoteRecognizerView: View {
    @StateObject private var vm = NoteRecognizerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            header
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            if let c = vm.confirmed {
                Label(c, systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundColor(.green)
            }
            controls
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Noten-Erkennung").font(.headline)
                Text("Vergleich mit den Samples").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button { vm.stop(); dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
            }
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
        case .analyzing:
            VStack(spacing: 12) {
                ProgressView()
                Text("Vergleiche mit Samples …").font(.subheadline).foregroundColor(.secondary)
            }
        case .choose:
            candidateList
        default:
            VStack(spacing: 10) {
                Image(systemName: "guitars").font(.system(size: 48)).foregroundColor(.accentColor)
                Text("Spiele einen Ton").font(.title2).bold()
                Text("Der Trainer vergleicht ihn mit den gespeicherten Samples und schlägt Positionen vor.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private var candidateList: some View {
        VStack(spacing: 12) {
            Text("Erkannt: \(vm.capturedNote) – welche Position war es?")
                .font(.subheadline).foregroundColor(.secondary)
            ForEach(vm.candidates) { c in
                Button { vm.choose(c) } label: { candidateRow(c) }
                    .buttonStyle(.plain)
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
                Text(c.noteName).font(.caption).foregroundColor(.secondary)
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
    enum State { case idle, listening, analyzing, choose, denied }

    @Published var state: State = .idle
    @Published var candidates: [ScoredCandidate] = []
    @Published var capturedNote: String = ""
    @Published var confirmed: String?
    @Published var isListening = false

    private let tuner = TunerEngine()
    private let audio = AudioEngine()
    private lazy var matcher = NoteMatcher(audio: audio)
    private var analyzing = false

    func start() {
        tuner.onNoteHeld = { [weak self] samples, sr, f0 in
            Task { @MainActor in await self?.handle(samples: samples, sampleRate: sr, f0: f0) }
        }
        tuner.start()
        isListening = true
        if state == .idle { state = .listening }
    }

    func stop() {
        tuner.stop()
        isListening = false
    }

    func toggle() {
        if isListening { stop() } else { start() }
    }

    private func handle(samples: [Float], sampleRate: Double, f0: Double) async {
        guard isListening, !analyzing else { return }
        analyzing = true
        capturedNote = BassIntro.noteName(forMidi: Int((69.0 + 12.0 * log2(f0 / 440.0)).rounded()))
        state = .analyzing
        let (cands, _) = await matcher.rank(input: samples, sampleRate: sampleRate, f0: f0)
        candidates = cands
        state = cands.isEmpty ? .listening : .choose
        analyzing = false
    }

    func choose(_ c: ScoredCandidate) {
        matcher.confirm(key: c.key)   // Feedback lernen: Fingerprint → Position
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
