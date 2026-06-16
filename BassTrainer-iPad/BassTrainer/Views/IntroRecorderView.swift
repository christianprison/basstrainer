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
        VStack(spacing: 20) {
            songHeader
            Text(vm.notes.isEmpty ? "Noch kein Anfang hinterlegt." : "\(vm.notes.count) Töne hinterlegt.")
                .foregroundColor(.secondary)
            Button { vm.startRecording() } label: {
                Label("Aufnahme starten", systemImage: "record.circle").font(.headline)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            if !vm.notes.isEmpty {
                Button("Vorhandene bearbeiten") { vm.phase = .edit }
            }
            Button("Anderen Song wählen") { vm.reset() }.font(.caption)
            Spacer()
        }
        .padding()
    }

    // MARK: - Aufnahme

    private func recordingView(countingIn: Bool) -> some View {
        VStack(spacing: 20) {
            songHeader
            Text(countingIn ? "Einzähler …" : "Spiele die ersten Töne")
                .font(.title3).foregroundColor(countingIn ? .secondary : .primary)
            ProgressView(value: Double(vm.level), total: 1).tint(.accentColor).padding(.horizontal, 40)
            Text("\(vm.captured.count) Töne erkannt").font(.caption).foregroundColor(.secondary)
            if !countingIn {
                Button(role: .destructive) { vm.stopRecording() } label: {
                    Label("Stopp", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal, 40)
            }
            Spacer()
        }
        .padding()
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
                Button { vm.startRecording() } label: { Label("Neu", systemImage: "record.circle") }
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

    private func stepper(systemImage: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemImage) }
            .buttonStyle(.borderless)
    }

    private func beatLabel(_ beat: Double) -> String {
        String(format: "%.2f", beat)
    }
}

// MARK: - Bass-Tab

/// Read-only Tabulatur: 4 Saitenlinien (oben G … unten E), Bundzahlen je Ton
/// in Spielreihenfolge. Horizontal scrollbar.
private struct BassTabView: View {
    let notes: [IntroNote]

    // Reihen oben→unten: G(5), D(4), A(3), E(2), B(1) — 5-Saiter.
    private let rows: [(label: String, string: Int)] = [("G", 5), ("D", 4), ("A", 3), ("E", 2), ("B", 1)]
    private let colWidth: CGFloat = 30

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.string) { row in
                    HStack(spacing: 0) {
                        Text(row.label)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        ForEach(notes) { note in
                            cell(fret: fret(of: note, on: row.string))
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(height: 140)
    }

    private func fret(of note: IntroNote, on string: Int) -> Int? {
        guard let sf = BassIntro.suggestStringFret(forMidi: note.midi), sf.string == string else { return nil }
        return sf.fret
    }

    private func cell(fret: Int?) -> some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.5)).frame(height: 1)
            if let fret {
                Text("\(fret)")
                    .font(.system(.callout, design: .monospaced))
                    .padding(.horizontal, 4)
                    .background(Color(.systemBackground))
            }
        }
        .frame(width: colWidth, height: 20)
    }
}

// MARK: - ViewModel

@MainActor
final class IntroRecorderViewModel: ObservableObject {
    enum Phase { case pickSong, ready, countIn, recording, edit, denied }

    @Published var phase: Phase = .pickSong
    @Published var songs: [CatalogSong] = []
    @Published var selectedSong: CatalogSong?
    @Published var notes: [IntroNote] = []
    @Published var captured: [(time: Double, midi: Int)] = []
    @Published var level: Float = 0
    @Published var status: String?
    @Published var saving = false

    let countInBeats = 4

    private let catalog = SongCatalog(source: .repertoire)
    private let recorder = IntroRecorder()
    private let repo = IntroRepository()
    private let audio = AudioEngine()

    private var scheduler: Timer?
    private var beatCounter = 0
    private var nextBeatTime: Double = 0
    private var downbeatTime: Double = 0
    private var recording = false

    private var bpm: Int { max(40, selectedSong?.bpm ?? 100) }
    private var beatDur: Double { 60.0 / Double(bpm) }

    func loadSongs() async {
        await catalog.load()
        songs = catalog.songs
    }

    func pick(_ song: CatalogSong) {
        selectedSong = song
        status = nil
        Task {
            notes = (try? await repo.load(songID: song.id)) ?? []
            phase = .ready
        }
    }

    // MARK: Aufnahme

    func startRecording() {
        captured = []
        status = nil
        recorder.onLevel = { [weak self] v in Task { @MainActor in self?.level = v } }
        recorder.onNote = { [weak self] t, midi, _ in Task { @MainActor in self?.gotNote(time: t, midi: midi) } }
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

    private func gotNote(time: Double, midi: Int) {
        guard recording, time >= downbeatTime - 0.05 else { return }
        captured.append((time, midi))
    }

    func stopRecording() {
        scheduler?.invalidate(); scheduler = nil
        recorder.stop()
        level = 0
        buildNotes()
        phase = .edit
    }

    private func buildNotes() {
        let sorted = captured.sorted { $0.time < $1.time }
        notes = sorted.enumerated().map { i, c in
            let beatRaw = (c.time - downbeatTime) / beatDur
            let beat = (beatRaw * 4).rounded() / 4    // auf Sechzehntel quantisieren
            return makeNote(idx: i + 1, midi: c.midi, beat: beat)
        }
    }

    private func makeNote(idx: Int, midi: Int, beat: Double) -> IntroNote {
        let sf = BassIntro.suggestStringFret(forMidi: midi)
        return IntroNote(idx: idx, midi: midi, beat: beat,
                         string: sf?.string, fret: sf?.fret, noteName: BassIntro.noteName(forMidi: midi))
    }

    // MARK: Korrektur

    func adjustMidi(_ note: IntroNote, by delta: Int) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[i].midi = max(24, min(72, notes[i].midi + delta))
        refresh(i)
    }

    func adjustBeat(_ note: IntroNote, by delta: Double) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[i].beat = ((notes[i].beat + delta) * 4).rounded() / 4
    }

    func deleteNote(_ note: IntroNote) {
        notes.removeAll { $0.id == note.id }
        reindex()
    }

    func addNote() {
        let beat = (notes.last?.beat ?? -1) + 1
        notes.append(makeNote(idx: notes.count + 1, midi: 28, beat: beat))
    }

    private func refresh(_ i: Int) {
        let sf = BassIntro.suggestStringFret(forMidi: notes[i].midi)
        notes[i].string = sf?.string
        notes[i].fret = sf?.fret
        notes[i].noteName = BassIntro.noteName(forMidi: notes[i].midi)
    }

    private func reindex() {
        for i in notes.indices { notes[i].idx = i + 1 }
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
                self?.audio.playSynthBass(frequency: BassIntro.frequency(forMidi: midi))
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
        recorder.stop()
        recording = false
        level = 0
    }
}
