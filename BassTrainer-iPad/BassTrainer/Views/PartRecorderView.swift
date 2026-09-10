import SwiftUI
import AVFoundation

/// Nimmt beim Mitspielen den eigenen Bass auf, zerlegt die Aufnahme nach Parts
/// und lässt jeden Teil bewerten: „gut" → als Referenz in die DB (Storage),
/// „verwerfen" → wird verworfen. Referenzen sind der spätere Maßstab.
struct PartRecorderView: View {
    let song: CatalogSong
    @ObservedObject var vm: SongDetailViewModel
    @ObservedObject var player: SongPlayer
    @StateObject private var rec = PartRecorderViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch rec.phase {
                case .idle:      idleView
                case .recording: recordingView
                case .review:    reviewView
                }
                if let s = rec.status { Text(s).font(.caption).foregroundColor(.secondary) }
                if !rec.references.isEmpty { referenceList }
            }
            .padding(20)
        }
        .onAppear { rec.configure(song: song, vm: vm, player: player) }
        .onDisappear { rec.cancel() }
    }

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Eigene Aufnahme").font(.headline)
            Text("Spiele den Song mit; die App nimmt deinen Bass (USB-DI) auf. Danach bewertest du jeden Teil – gute Teile werden als Referenz gespeichert.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if !vm.hasTiming {
                Label("Für diesen Song ist keine Timeline hinterlegt – Aufnahme kann nicht in Teile zerlegt werden.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.orange)
            }
            Button { rec.startRecording() } label: {
                Label("Aufnahme starten", systemImage: "record.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!vm.hasTiming || !player.hasTrack)
        }
    }

    private var recordingView: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "record.circle.fill").foregroundColor(.red)
                Text("Aufnahme läuft – spiele mit").font(.headline)
                Spacer()
                Text(time(player.progress)).font(.subheadline).monospacedDigit().foregroundColor(.secondary)
            }
            ProgressView(value: Double(rec.level), total: 1).tint(.red)
            Text("Input: \(rec.inputName)").font(.caption2).foregroundColor(.secondary)
            Button(role: .destructive) { rec.stopRecording() } label: {
                Label("Stopp & bewerten", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Teile bewerten").font(.headline)
            Text("Höre jeden Teil an und entscheide: gut = als Referenz speichern, sonst verwerfen.")
                .font(.caption).foregroundColor(.secondary)
            ForEach(rec.segments) { seg in segmentRow(seg) }
            Button { rec.reset() } label: { Label("Neue Aufnahme", systemImage: "arrow.counterclockwise") }
                .font(.caption).padding(.top, 4)
        }
    }

    private func segmentRow(_ seg: PartRecorderViewModel.Segment) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(seg.name.isEmpty ? "Takt \(seg.startBar)" : seg.name).font(.subheadline).fontWeight(.medium)
                Text("Takt \(seg.startBar)–\(seg.endBar) · \(time(seg.endTime - seg.startTime))")
                    .font(.caption2).foregroundColor(.secondary).monospacedDigit()
            }
            Spacer()
            switch seg.decision {
            case .kept:
                Label("Referenz", systemImage: "checkmark.seal.fill").font(.caption).foregroundColor(.green)
            case .discarded:
                Label("verworfen", systemImage: "xmark").font(.caption).foregroundColor(.secondary)
            case .undecided:
                Button { rec.playSegment(seg) } label: { Image(systemName: rec.playingSegmentID == seg.id ? "stop.circle" : "play.circle") }
                    .buttonStyle(.borderless)
                Button { rec.keep(seg) } label: { Image(systemName: "hand.thumbsup.fill") }
                    .buttonStyle(.borderless).tint(.green)
                Button { rec.discard(seg) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).tint(.red)
            }
        }
        .padding(.vertical, 6)
        .overlay(Divider(), alignment: .bottom)
    }

    private var referenceList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gespeicherte Referenzen").font(.caption).foregroundColor(.secondary).padding(.top, 8)
            ForEach(rec.references) { ref in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                    Text(ref.partName.isEmpty ? "Takt \(ref.startBar)" : ref.partName).font(.subheadline)
                    Spacer()
                    Button { rec.listen(ref) } label: { Image(systemName: "speaker.wave.2") }.buttonStyle(.borderless)
                    Button { Task { await rec.deleteReference(ref) } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).tint(.red)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func time(_ s: Double) -> String {
        let t = max(0, Int(s.rounded()))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - ViewModel

@MainActor
final class PartRecorderViewModel: ObservableObject {
    enum Phase { case idle, recording, review }
    enum Decision { case undecided, kept, discarded }

    struct Segment: Identifiable {
        let id = UUID()
        let name: String
        let startBar: Int
        let endBar: Int
        let startTime: Double
        let endTime: Double
        var decision: Decision = .undecided
    }

    @Published var phase: Phase = .idle
    @Published var level: Float = 0
    @Published var segments: [Segment] = []
    @Published var status: String?
    @Published var playingSegmentID: UUID?
    @Published var references: [PartReference] = []
    @Published var inputName = "—"

    private let recorder = PartRecorder()
    private let store = PartReferenceStore()
    private var song: CatalogSong?
    private weak var vm: SongDetailViewModel?
    private weak var player: SongPlayer?
    private var recSamples: [Float] = []
    private var recSR: Double = 48000
    private var slicePlayer: AVAudioPlayer?
    private var didLoad = false

    func configure(song: CatalogSong, vm: SongDetailViewModel, player: SongPlayer) {
        self.song = song; self.vm = vm; self.player = player
        if !didLoad { didLoad = true; Task { await loadRefs() } }
    }

    private func loadRefs() async {
        guard let song else { return }
        await store.load(songID: song.id)
        references = store.references
        status = store.status
    }

    func startRecording() {
        guard let player, vm?.hasTiming == true else { return }
        status = nil; segments = []
        recorder.onLevel = { [weak self] v in DispatchQueue.main.async { self?.level = v } }
        recorder.start { [weak self] ok in
            guard let self else { return }
            if ok {
                self.inputName = self.recorder.inputName
                player.setBaseRate(1.0)
                player.seek(to: 0)
                if !player.isPlaying { player.toggle() }
                self.phase = .recording
            } else {
                self.status = "Kein Mikrofon-Zugriff."
            }
        }
    }

    func stopRecording() {
        let out = recorder.stop()
        player?.pause()
        recSamples = out.samples
        recSR = out.sampleRate
        buildSegments()
        phase = .review
    }

    /// Aufnahme abbrechen (View verschwindet).
    func cancel() {
        if phase == .recording { _ = recorder.stop(); player?.pause() }
        slicePlayer?.stop(); slicePlayer = nil
        playingSegmentID = nil
    }

    private func buildSegments() {
        guard let vm else { segments = []; return }
        let parts = vm.parts.sorted { $0.startBar < $1.startBar }
        guard !parts.isEmpty else { segments = []; return }
        let total = player?.duration ?? (Double(recSamples.count) / recSR)
        var result: [Segment] = []
        for (i, part) in parts.enumerated() {
            let start = vm.startTime(forBar: part.startBar) ?? 0
            let endBar = (i + 1 < parts.count) ? parts[i + 1].startBar - 1 : (vm.totalBars ?? part.startBar)
            let end = (i + 1 < parts.count) ? (vm.startTime(forBar: parts[i + 1].startBar) ?? total) : total
            guard end > start + 0.2 else { continue }
            result.append(Segment(name: part.name, startBar: part.startBar, endBar: max(part.startBar, endBar),
                                  startTime: start, endTime: end))
        }
        segments = result
    }

    private func slice(_ seg: Segment) -> [Float] {
        let s = max(0, Int(seg.startTime * recSR))
        let e = min(recSamples.count, Int(seg.endTime * recSR))
        guard e > s else { return [] }
        return Array(recSamples[s..<e])
    }

    func playSegment(_ seg: Segment) {
        if playingSegmentID == seg.id { slicePlayer?.stop(); slicePlayer = nil; playingSegmentID = nil; return }
        let data = WAVEncoder.encode(slice(seg), sampleRate: recSR)
        playData(data, id: seg.id)
    }

    private func playData(_ data: Data, id: UUID) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
            slicePlayer = p
            p.play()
            playingSegmentID = id
        } catch {
            status = "Wiedergabe fehlgeschlagen."
        }
    }

    func keep(_ seg: Segment) {
        guard let song else { return }
        let samples = slice(seg)
        guard !samples.isEmpty else { discard(seg); return }
        let env = Self.envelope(samples, buckets: 64)
        markDecision(seg.id, .kept)
        Task {
            do {
                try await store.saveReference(songID: song.id, partName: seg.name,
                                              startBar: seg.startBar, endBar: seg.endBar,
                                              samples: samples, sampleRate: recSR, envelope: env)
                references = store.references
                status = store.status
            } catch {
                status = "Upload fehlgeschlagen: \(error.localizedDescription)"
                markDecision(seg.id, .undecided)
            }
        }
    }

    func discard(_ seg: Segment) { markDecision(seg.id, .discarded) }

    private func markDecision(_ id: UUID, _ d: Decision) {
        if let i = segments.firstIndex(where: { $0.id == id }) { segments[i].decision = d }
    }

    func reset() {
        segments = []; recSamples = []; status = nil
        slicePlayer?.stop(); slicePlayer = nil; playingSegmentID = nil
        phase = .idle
    }

    func listen(_ ref: PartReference) {
        Task {
            guard let url = await store.playbackURL(for: ref) else { status = "Keine Wiedergabe-URL."; return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                playData(data, id: UUID())
            } catch { status = "Referenz konnte nicht geladen werden." }
        }
    }

    func deleteReference(_ ref: PartReference) async {
        await store.delete(ref)
        references = store.references
    }

    /// Grobe RMS-Hüllkurve (0…1) in `buckets` Werten – Basis für Phase 2.
    private static func envelope(_ samples: [Float], buckets: Int) -> [Double] {
        guard samples.count >= buckets, buckets > 0 else { return [] }
        let per = samples.count / buckets
        var out = [Double](repeating: 0, count: buckets)
        for b in 0..<buckets {
            let a = b * per, z = min(samples.count, a + per)
            var sum = 0.0
            for i in a..<z { sum += Double(samples[i]) * Double(samples[i]) }
            out[b] = (sum / Double(max(1, z - a))).squareRoot()
        }
        let peak = out.max() ?? 1
        if peak > 0 { for i in out.indices { out[i] /= peak } }
        return out
    }
}
