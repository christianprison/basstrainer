import SwiftUI
import QuartzCore

/// Kurator-Übung „Intro einspielen": Anfänge einspielen, korrigieren und
/// direkt in die zentrale DB schreiben (DELETE+POST). Nur Kuratoren dürfen
/// schreiben — sonst sauberer 403-Hinweis.
struct IntroRecorderView: View {
    @StateObject private var vm = IntroRecorderViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Intro einspielen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { vm.stopAll(); dismiss() } label: { Label("Menü", systemImage: "chevron.left") }
                    }
                }
        }
        .task { if vm.songs.isEmpty { await vm.loadSongs() } }
        .onDisappear { vm.stopAll() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .pickSong: songPicker
        case .ready:    readyView
        case .countIn:  recordingView(countingIn: true)
        case .recording: recordingView(countingIn: false)
        case .analyze:  analyzeView
        case .edit:     editView
        case .denied:   deniedView
        }
    }

    // MARK: - Songauswahl

    private var songPicker: some View {
        Group {
            if vm.songs.isEmpty {
                ProgressView("Lade Songs …")
            } else {
                List(vm.songs) { song in
                    Button { vm.pick(song) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(song.name)
                                if let artist = song.artist { Text(artist).font(.caption).foregroundColor(.secondary) }
                            }
                            Spacer()
                            if let bpm = song.bpm { Text("\(bpm) BPM").font(.caption).foregroundColor(.secondary) }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
        }
    }

    // MARK: - Bereit

    private var readyView: some View {
        ScrollView {
            VStack(spacing: 20) {
                songHeader
                Text(vm.notes.isEmpty ? "Noch kein Anfang hinterlegt." : "\(vm.notes.count) Töne hinterlegt.")
                    .foregroundColor(.secondary)
                if !vm.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gespeicherter Anfang").font(.caption).foregroundColor(.secondary)
                        BassTabView(notes: vm.notes)
                    }
                    .padding(.horizontal)
                }
                Stepper(value: $vm.tempo, in: 40...240, step: 1) {
                    Label("Tempo: \(Int(vm.tempo)) BPM", systemImage: "metronome")
                }
                .padding(.horizontal, 30)
                detectionSettings
                Button { vm.startRecording() } label: {
                    Label("Aufnahme starten", systemImage: "record.circle").font(.headline)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                if !vm.notes.isEmpty {
                    Button("Vorhandene bearbeiten") { vm.phase = .edit }
                }
                Button("Anderen Song wählen") { vm.reset() }.font(.caption)
            }
            .padding()
        }
    }

    // MARK: - Aufnahme

    private func recordingView(countingIn: Bool) -> some View {
        VStack(spacing: 24) {
            Spacer()
            songHeader
            Image(systemName: countingIn ? "metronome.fill" : "record.circle.fill")
                .font(.system(size: 54))
                .foregroundColor(countingIn ? .secondary : .red)
            Text(countingIn ? "Einzähler … (\(vm.countInBeats) Schläge)" : "Spiele die ersten Töne")
                .font(.title2).foregroundColor(countingIn ? .secondary : .primary)
            ProgressView(value: Double(vm.level), total: 1).tint(.accentColor).padding(.horizontal, 60)
            if !countingIn {
                Text("Wird aufgezeichnet – Erkennung folgt nach dem Stopp.")
                    .font(.caption).foregroundColor(.secondary)
                Button(role: .destructive) { vm.stopRecording() } label: {
                    Label("Stopp", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal, 60)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Analyse (Offline-Erkennung tweaken)

    private var analyzeView: some View {
        ScrollView {
            VStack(spacing: 16) {
                songHeader
                Text("\(vm.captured.count) Töne erkannt").font(.caption).foregroundColor(.secondary)
                if !vm.captured.isEmpty {
                    BassTabView(notes: vm.capturedNotes).padding(.horizontal)
                }
                WaveformMeterView(samples: vm.meter).padding(.horizontal)
                Text("Regler verschieben → Erkennung wird auf der Aufnahme neu berechnet.")
                    .font(.caption2).foregroundColor(.secondary)
                detectionSettings
                HStack {
                    Button { vm.phase = .ready } label: { Label("Neu aufnehmen", systemImage: "record.circle") }
                    Spacer()
                    Button { vm.phase = .edit } label: { Label("Übernehmen", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 30).padding(.top, 4)
            }
            .padding()
        }
    }

    // MARK: - Korrektur

    private var editView: some View {
        VStack(spacing: 0) {
            if !vm.notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bass-Tab").font(.caption).foregroundColor(.secondary)
                    BassTabView(notes: vm.notes)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Divider()
            }
            List {
                Section {
                    ForEach(vm.notes) { note in noteRow(note) }
                } header: {
                    Text("Töne (\(vm.notes.count)) – Tonhöhe & Schlag korrigieren")
                }
            }
            controls
        }
    }

    private func noteRow(_ note: IntroNote) -> some View {
        HStack(spacing: 12) {
            Text("\(note.idx)").font(.caption).monospacedDigit().foregroundColor(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(BassIntro.noteName(forMidi: note.midi)).font(.headline)
                if let sf = BassIntro.suggestStringFret(forMidi: note.midi) {
                    Text("\(BassIntro.stringName[sf.string] ?? "?")-Saite, Bund \(sf.fret)").font(.caption2).foregroundColor(.secondary)
                }
            }
            stepper(systemImage: "minus") { vm.adjustMidi(note, by: -1) }
            stepper(systemImage: "plus") { vm.adjustMidi(note, by: +1) }
            Divider().frame(height: 24)
            Text("Schlag \(beatLabel(note.beat))").font(.caption).monospacedDigit().frame(width: 78)
            stepper(systemImage: "chevron.left") { vm.adjustBeat(note, by: -0.25) }
            stepper(systemImage: "chevron.right") { vm.adjustBeat(note, by: +0.25) }
            Button(role: .destructive) { vm.deleteNote(note) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if let status = vm.status {
                Text(status).font(.caption).foregroundColor(status.hasPrefix("Gespeichert") ? .green : .orange)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Button { vm.addNote() } label: { Label("Ton", systemImage: "plus") }
                Spacer()
                Button { vm.preview() } label: { Label("Vorschau", systemImage: "play") }
                Spacer()
                Button { vm.phase = .ready } label: { Label("Neu", systemImage: "record.circle") }
            }
            Button { vm.save() } label: {
                Label(vm.saving ? "Speichere …" : "In Datenbank speichern", systemImage: "icloud.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(vm.saving || vm.notes.isEmpty)
        }
        .padding()
    }

    private var deniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash.fill").font(.system(size: 40)).foregroundColor(.secondary)
            Text("Kein Mikrofon-Zugriff. Bitte in Einstellungen → Datenschutz → Mikrofon aktivieren.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).padding()
            Button("Zurück") { vm.phase = .ready }.buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Bausteine

    private var songHeader: some View {
        VStack(spacing: 4) {
            Text(vm.selectedSong?.name ?? "—").font(.title2).bold()
            if let bpm = vm.selectedSong?.bpm { Text("\(bpm) BPM").font(.caption).foregroundColor(.secondary) }
        }
    }

    private var detectionSettings: some View {
        VStack(spacing: 6) {
            paramSlider("Empfindlichkeit", $vm.sensitivity, 0...1) { "\(Int($0 * 100)) %" }
            paramSlider("Gain", $vm.gain, 1...40) { String(format: "%.0f×", $0) }
            paramSlider("Gate", $vm.gate, 0...0.15) { String(format: "%.3f", $0) }
            paramSlider("Attack", $vm.attack, 0.1...0.9) { String(format: "%.2f", $0) }
            paramSlider("Release", $vm.release, 0.005...0.1) { String(format: "%.3f", $0) }
            paramSlider("Refraktär", $vm.refractory, 40...200) { "\(Int($0)) ms" }
            Button("Standardwerte") { vm.resetParams() }.font(.caption).padding(.top, 2)
        }
        .padding(.horizontal, 30)
    }

    private func paramSlider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                             format: @escaping (Double) -> String) -> some View {
        VStack(spacing: 1) {
            HStack {
                Text(title).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(format(value.wrappedValue)).font(.caption2).monospacedDigit().foregroundColor(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func stepper(systemImage: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemImage) }
            .buttonStyle(.borderless)
    }

    private func beatLabel(_ beat: Double) -> String {
        String(format: "%.2f", beat)
    }
}

// MARK: - Bass-Tab

/// Read-only Tabulatur: 5 Saitenlinien (oben G … unten B). Töne werden
/// **rhythmisch** nach ihrer Position im Takt platziert, mit Taktstrichen
/// (4/4) und Dauer-Unterstrich. Horizontal scrollbar.
struct BassTabView: View {
    let notes: [IntroNote]

    // Reihen oben→unten: G(5), D(4), A(3), E(2), B(1) — 5-Saiter.
    private let rows: [(label: String, string: Int)] = [("G", 5), ("D", 4), ("A", 3), ("E", 2), ("B", 1)]
    private let beatWidth: CGFloat = 30      // pt pro Viertel
    private let rowHeight: CGFloat = 22
    private let leftPad: CGFloat = 22
    private let topPad: CGFloat = 10

    private var firstBeat: Double { notes.map { $0.beat }.min() ?? 0 }
    private var lastEnd: Double { notes.map { $0.beat + ($0.durationBeats ?? 0.25) }.max() ?? 4 }
    private var originBeat: Double { min(0, (firstBeat / 4).rounded(.down) * 4) }
    private var endBeat: Double { max(originBeat + 4, (lastEnd / 4).rounded(.up) * 4) }

    private var totalWidth: CGFloat { leftPad + CGFloat(endBeat - originBeat) * beatWidth + 12 }
    private var totalHeight: CGFloat { topPad * 2 + CGFloat(rows.count - 1) * rowHeight }

    private func x(_ beat: Double) -> CGFloat { leftPad + CGFloat(beat - originBeat) * beatWidth }
    private func rowY(_ string: Int) -> CGFloat {
        let idx = rows.firstIndex { $0.string == string } ?? 0
        return topPad + CGFloat(idx) * rowHeight
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Canvas { ctx, size in
                // Saitenlinien + Labels
                for (idx, row) in rows.enumerated() {
                    let y = topPad + CGFloat(idx) * rowHeight
                    var line = Path()
                    line.move(to: CGPoint(x: leftPad, y: y))
                    line.addLine(to: CGPoint(x: size.width - 6, y: y))
                    ctx.stroke(line, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                    ctx.draw(Text(row.label).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary),
                             at: CGPoint(x: 9, y: y))
                }

                // Taktstriche (alle 4 Viertel)
                let bottom = topPad + CGFloat(rows.count - 1) * rowHeight
                var b = originBeat
                while b <= endBeat + 0.001 {
                    var bar = Path()
                    bar.move(to: CGPoint(x: x(b), y: topPad - 5))
                    bar.addLine(to: CGPoint(x: x(b), y: bottom + 5))
                    ctx.stroke(bar, with: .color(.secondary.opacity(0.7)), lineWidth: b == 0 ? 1.6 : 1)
                    b += 4
                }

                // Noten
                for note in notes {
                    guard let sf = BassIntro.suggestStringFret(forMidi: note.midi) else { continue }
                    let nx = x(note.beat)
                    let ny = rowY(sf.string)
                    let dur = note.durationBeats ?? 0.25
                    if dur > 0 {
                        var d = Path()
                        d.move(to: CGPoint(x: nx, y: ny + 9))
                        d.addLine(to: CGPoint(x: x(note.beat + dur) - 2, y: ny + 9))
                        ctx.stroke(d, with: .color(.accentColor.opacity(0.5)), lineWidth: 2)
                    }
                    let resolved = ctx.resolve(
                        Text("\(sf.fret)").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.primary)
                    )
                    let ts = resolved.measure(in: CGSize(width: 50, height: 20))
                    let rect = CGRect(x: nx - ts.width / 2 - 2, y: ny - ts.height / 2, width: ts.width + 4, height: ts.height)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color(.systemBackground)))
                    ctx.draw(resolved, at: CGPoint(x: nx, y: ny))
                }
            }
            .frame(width: totalWidth, height: totalHeight)
            .padding(.vertical, 6)
        }
        .frame(height: totalHeight + 16)
    }
}

// MARK: - Erkennungs-Visualisierung

/// Ein Telemetrie-Punkt der Onset-Erkennung (für die Live-Wellenform).
struct DetectionMeterSample {
    let env: Float          // Pegel (gainverstärkt, geglättet)
    let threshold: Float    // adaptive Schwelle (Gate + Empfindlichkeit)
    let onset: Bool         // hier wurde ein Anschlag erkannt
}

/// Live-Hüllkurve: Pegel (Fläche), adaptive Schwelle (gestrichelt) und
/// Anschlag-Marker (vertikal). Zeigt direkt, wie die Regler wirken.
struct WaveformMeterView: View {
    let samples: [DetectionMeterSample]

    var body: some View {
        Canvas { ctx, size in
            guard samples.count > 1 else { return }
            let maxV = max(0.05, samples.map { max($0.env, $0.threshold) }.max() ?? 0.05)
            let dx = size.width / CGFloat(samples.count - 1)
            func y(_ v: Float) -> CGFloat { size.height - CGFloat(v) / CGFloat(maxV) * size.height }

            // Pegel als Fläche
            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height))
            for (i, s) in samples.enumerated() { area.addLine(to: CGPoint(x: CGFloat(i) * dx, y: y(s.env))) }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            ctx.fill(area, with: .color(.accentColor.opacity(0.25)))

            // Pegel-Linie
            var line = Path()
            for (i, s) in samples.enumerated() {
                let p = CGPoint(x: CGFloat(i) * dx, y: y(s.env))
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            ctx.stroke(line, with: .color(.accentColor), lineWidth: 1.5)

            // Schwelle (gestrichelt)
            var thr = Path()
            for (i, s) in samples.enumerated() {
                let p = CGPoint(x: CGFloat(i) * dx, y: y(s.threshold))
                if i == 0 { thr.move(to: p) } else { thr.addLine(to: p) }
            }
            ctx.stroke(thr, with: .color(.orange), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            // Anschlag-Marker
            for (i, s) in samples.enumerated() where s.onset {
                var m = Path()
                m.move(to: CGPoint(x: CGFloat(i) * dx, y: 0))
                m.addLine(to: CGPoint(x: CGFloat(i) * dx, y: size.height))
                ctx.stroke(m, with: .color(.green), lineWidth: 1.5)
            }
        }
        .frame(height: 90)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 10) {
                legend(color: .accentColor, text: "Pegel")
                legend(color: .orange, text: "Schwelle")
                legend(color: .green, text: "Anschlag")
            }
            .font(.caption2)
            .padding(6)
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).foregroundColor(.secondary)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class IntroRecorderViewModel: ObservableObject {
    enum Phase { case pickSong, ready, countIn, recording, analyze, edit, denied }

    @Published var phase: Phase = .pickSong
    @Published var songs: [CatalogSong] = []
    @Published var selectedSong: CatalogSong?
    @Published var notes: [IntroNote] = []
    @Published var captured: [(time: Double, midi: Int)] = []
    @Published var level: Float = 0
    @Published var meter: [DetectionMeterSample] = []
    @Published var status: String?
    @Published var saving = false
    @Published var tempo: Double = 100   // Einspiel-Tempo (BPM), anpassbar
    @Published var sensitivity: Double = 0.6 { didSet { recorder.sensitivity = Float(sensitivity); analysisDirty() } }
    @Published var gain: Double = 12        { didSet { recorder.inputGain = Float(gain); analysisDirty() } }
    @Published var gate: Double = 0.02      { didSet { recorder.gate = Float(gate); analysisDirty() } }
    @Published var attack: Double = 0.4     { didSet { recorder.attack = Float(attack); analysisDirty() } }
    @Published var release: Double = 0.02   { didSet { recorder.release = Float(release); analysisDirty() } }
    @Published var refractory: Double = 70  { didSet { recorder.refractoryMs = refractory; analysisDirty() } }

    func applyParams() {
        recorder.sensitivity = Float(sensitivity)
        recorder.inputGain = Float(gain)
        recorder.gate = Float(gate)
        recorder.attack = Float(attack)
        recorder.release = Float(release)
        recorder.refractoryMs = refractory
    }

    func resetParams() {
        sensitivity = 0.6; gain = 12; gate = 0.02; attack = 0.4; release = 0.02; refractory = 70
    }

    let countInBeats = 8   // 2 Takte 4/4

    private let catalog = SongCatalog(source: .repertoire)
    private let recorder = IntroRecorder()
    private let repo = IntroRepository()
    private let audio = AudioEngine()

    /// Erkannte Töne der laufenden Aufnahme als Tab-fähige Notenliste.
    var capturedNotes: [IntroNote] {
        var arr = captured.enumerated().map { i, c in
            let sf = BassIntro.suggestStringFret(forMidi: c.midi)
            return IntroNote(idx: i + 1, midi: c.midi, beat: q16((c.time - downbeatTime) / beatDur),
                             string: sf?.string, fret: sf?.fret, noteName: BassIntro.noteName(forMidi: c.midi))
        }
        applyDurations(&arr)
        return arr
    }

    private var scheduler: Timer?
    private var beatCounter = 0
    private var nextBeatTime: Double = 0
    private var downbeatTime: Double = 0
    private var recording = false

    // Aufgezeichnete Audiospur für die Offline-Analyse.
    private var recordedSamples: [Float] = []
    private var recordedStartTime: Double = 0
    private var recordedSampleRate: Double = 48000
    private var analyzeTask: Task<Void, Never>?

    private var beatDur: Double { 60.0 / max(40, tempo) }

    func loadSongs() async {
        await catalog.load()
        songs = catalog.songs
    }

    func pick(_ song: CatalogSong) {
        selectedSong = song
        tempo = Double(song.bpm ?? 100)
        status = nil
        Task {
            notes = (try? await repo.load(songID: song.id)) ?? []
            phase = .ready
        }
    }

    // MARK: Aufnahme

    func startRecording() {
        captured = []
        meter = []
        notes = []
        status = nil
        applyParams()
        recorder.captureRaw = true                       // ganze Spur mitschneiden
        recorder.onLevel = { [weak self] v in Task { @MainActor in self?.level = v } }
        recorder.onMeter = nil
        recorder.onNote = nil                            // Erkennung läuft offline nach dem Stop
        recorder.start { [weak self] granted in
            guard let self else { return }
            if granted { self.beginCountIn() } else { self.phase = .denied }
        }
    }

    private func beginCountIn() {
        phase = .countIn
        recording = false
        beatCounter = 0
        nextBeatTime = CACurrentMediaTime() + 0.5
        downbeatTime = nextBeatTime + Double(countInBeats) * beatDur
        scheduler = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        while nextBeatTime < now + 0.15 {
            recorder.scheduleTick(accent: beatCounter % 4 == 0, at: nextBeatTime)
            beatCounter += 1
            nextBeatTime += beatDur
        }
        if !recording && now >= downbeatTime {
            recording = true
            phase = .recording
        }
    }

    func stopRecording() {
        scheduler?.invalidate(); scheduler = nil
        let raw = recorder.rawAudio()
        recorder.stop()
        level = 0
        recordedSamples = raw.samples
        recordedStartTime = raw.startTime
        recordedSampleRate = raw.sampleRate
        runAnalysis()
        phase = .analyze
    }

    /// Offline-Erkennung auf der aufgezeichneten Spur mit den aktuellen Parametern.
    func runAnalysis() {
        guard !recordedSamples.isEmpty, recordedStartTime >= 0 else { return }
        let dbIdx = max(0, Int((downbeatTime - recordedStartTime) * recordedSampleRate))
        guard dbIdx < recordedSamples.count else { return }
        let slice = Array(recordedSamples[dbIdx...])
        let p = IntroAnalyzer.Params(sensitivity: Float(sensitivity), gain: Float(gain), gate: Float(gate),
                                     attack: Float(attack), release: Float(release), refractoryMs: refractory)
        let result = IntroAnalyzer.analyze(samples: slice, sampleRate: recordedSampleRate, startTime: downbeatTime, params: p)
        captured = result.notes.map { (time: $0.time, midi: $0.midi) }
        meter = result.meter
        buildNotes()
    }

    /// Re-Analyse (debounced) nach Parameteränderung — nur im Analyse-Schritt.
    private func analysisDirty() {
        guard phase == .analyze else { return }
        analyzeTask?.cancel()
        analyzeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self, !Task.isCancelled else { return }
            self.runAnalysis()
        }
    }

    private func buildNotes() {
        let sorted = captured.sorted { $0.time < $1.time }
        var result = sorted.enumerated().map { i, c in
            makeNote(idx: i + 1, midi: c.midi, beat: q16((c.time - downbeatTime) / beatDur))
        }
        applyDurations(&result)
        notes = result
    }

    private func makeNote(idx: Int, midi: Int, beat: Double) -> IntroNote {
        let sf = BassIntro.suggestStringFret(forMidi: midi)
        return IntroNote(idx: idx, midi: midi, beat: beat,
                         string: sf?.string, fret: sf?.fret, noteName: BassIntro.noteName(forMidi: midi))
    }

    private func q16(_ b: Double) -> Double { (b * 4).rounded() / 4 }

    /// Setzt Notendauern aus dem Abstand zum nächsten Anschlag (16tel-quantisiert),
    /// sortiert chronologisch und reindiziert. Letzte Note = Viertel-Default.
    private func applyDurations(_ arr: inout [IntroNote]) {
        var s = arr.sorted { $0.beat < $1.beat }
        for i in s.indices {
            if i + 1 < s.count {
                s[i].durationBeats = min(4, max(0.25, q16(s[i + 1].beat - s[i].beat)))
            } else {
                s[i].durationBeats = 1.0
            }
            s[i].idx = i + 1
        }
        arr = s
    }

    // MARK: Korrektur

    func adjustMidi(_ note: IntroNote, by delta: Int) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[i].midi = max(24, min(72, notes[i].midi + delta))
        refresh(i)
    }

    func adjustBeat(_ note: IntroNote, by delta: Double) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[i].beat = q16(notes[i].beat + delta)
        applyDurations(&notes)
    }

    func deleteNote(_ note: IntroNote) {
        notes.removeAll { $0.id == note.id }
        applyDurations(&notes)
    }

    func addNote() {
        let beat = (notes.map { $0.beat }.max() ?? -1) + 1
        notes.append(makeNote(idx: notes.count + 1, midi: 28, beat: beat))
        applyDurations(&notes)
    }

    private func refresh(_ i: Int) {
        let sf = BassIntro.suggestStringFret(forMidi: notes[i].midi)
        notes[i].string = sf?.string
        notes[i].fret = sf?.fret
        notes[i].noteName = BassIntro.noteName(forMidi: notes[i].midi)
    }

    // MARK: Vorschau / Speichern

    func preview() {
        let lead = 0.4
        for b in 0..<countInBeats {
            schedule(after: lead + Double(b) * beatDur) { [weak self] in
                self?.audio.playMetronomeClick(accent: b % 4 == 0)
            }
        }
        let base = lead + Double(countInBeats) * beatDur
        for n in notes {
            let t = base + n.beat * beatDur
            guard t >= 0 else { continue }
            let midi = n.midi
            schedule(after: t) { [weak self] in
                self?.audio.playBassNote(position: BassIntro.fretPosition(forMidi: midi))
            }
        }
    }

    private func schedule(after delay: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    func save() {
        guard let song = selectedSong else { return }
        saving = true
        status = nil
        Task {
            do {
                try await repo.save(songID: song.id, notes: notes)
                status = "Gespeichert ✓ (\(notes.count) Töne)"
            } catch let e as SupabaseConfig.RESTError {
                if case .forbidden = e {
                    status = "Nicht freigeschaltet – uid (Einstellungen) in „curators“ eintragen lassen."
                } else {
                    status = e.localizedDescription
                }
            } catch {
                status = error.localizedDescription
            }
            saving = false
        }
    }

    func reset() {
        stopAll()
        phase = .pickSong
        selectedSong = nil
        notes = []
        captured = []
        status = nil
    }

    func stopAll() {
        scheduler?.invalidate(); scheduler = nil
        analyzeTask?.cancel(); analyzeTask = nil
        recorder.stop()
        recording = false
        level = 0
    }
}
