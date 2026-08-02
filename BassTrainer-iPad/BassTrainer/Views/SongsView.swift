import SwiftUI

/// Songs-Übung mit 3-Zonen-Layout:
///  - links 20 %: Song-Navigation (Auswahl)
///  - oben rechts (80 % × 20 %): Statuszeile (Name, Metronom, Play/Pause)
///  - unten rechts (80 % × 80 %): Hauptbereich – Parts (Zeilen) × Takte (Spalten)
struct SongsView: View {
    let source: SongSource

    @StateObject private var catalog: SongCatalog
    @StateObject private var player = SongPlayer()
    @StateObject private var metronome = Metronome()
    @StateObject private var detail = SongDetailViewModel()
    @StateObject private var markerStore = PracticeMarkerStore()
    @State private var selectedID: String?
    @State private var mainTab: MainTab = .lyrics
    @State private var practiceTempo: Double = 1.0   // Playback- & Metronom-Tempo (1.0 = Normal)
    @Environment(\.dismiss) private var dismiss

    private enum MainTab { case lyrics, bars }

    // Statuszeile so hoch wie der Play-Button (44) + 20 px.
    private let statusBarHeight: CGFloat = 64

    init(source: SongSource) {
        self.source = source
        _catalog = StateObject(wrappedValue: SongCatalog(source: source))
    }

    private var selectedSong: CatalogSong? {
        catalog.songs.first { $0.id == selectedID }
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                songNav
                    .frame(width: geo.size.width * 0.2)
                    .background(Color(.secondarySystemBackground))
                Divider()
                workArea
                    .frame(width: geo.size.width * 0.8)
            }
        }
        .background(Color(.systemBackground))
        .task {
            if catalog.songs.isEmpty {
                await catalog.load()
                if selectedID == nil { selectSong(catalog.songs.first) }
            }
        }
        .onChange(of: player.progress) { _, t in detail.update(currentTime: t) }
        .onDisappear { player.stop(); metronome.stop() }
    }

    // MARK: - Links: Song-Navigation (20 %)

    private var songNav: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                Text(source.title).font(.headline).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider()

            if catalog.isLoading {
                Spacer(); ProgressView(); Spacer()
            } else if let error = catalog.error {
                Spacer()
                VStack(spacing: 8) {
                    Text("Fehler").font(.subheadline).bold()
                    Text(error).font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button("Erneut") { Task { await catalog.load(); selectSong(catalog.songs.first) } }
                        .font(.caption).buttonStyle(.bordered)
                }.padding(8)
                Spacer()
            } else {
                List(catalog.songs, selection: Binding(
                    get: { selectedID },
                    set: { id in selectSong(catalog.songs.first { $0.id == id }) }
                )) { song in
                    navRow(song).tag(song.id)
                }
                .listStyle(.plain)
            }
        }
    }

    private func navRow(_ song: CatalogSong) -> some View {
        HStack(spacing: 8) {
            if let pos = song.pos {
                Text("\(pos)").font(.caption).monospacedDigit().foregroundColor(.secondary)
                    .frame(width: 20, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.name).font(.subheadline).lineLimit(1)
                if let artist = song.artist {
                    Text(artist).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if song.hasPlayalong {
                Image(systemName: "music.note").font(.caption2).foregroundColor(.accentColor)
            }
        }
        .opacity(song.hasPlayalong || !song.snippetBars.isEmpty ? 1 : 0.5)
    }

    // MARK: - Rechts: Arbeitsbereich (80 %)

    private var workArea: some View {
        VStack(spacing: 0) {
            statusBar
                .frame(height: statusBarHeight)
            Divider()
            mainArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // Oben rechts (20 % Höhe): Name + Metronom + Play/Pause
    private var statusBar: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedSong?.name ?? "—").font(.title2).bold().lineLimit(1)
                HStack(spacing: 12) {
                    if let artist = selectedSong?.artist { Text(artist) }
                    if let bpm = selectedSong?.bpm { Label("\(bpm) BPM", systemImage: "metronome") }
                    if let key = selectedSong?.musicKey { Label(key, systemImage: "music.note") }
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()

            tempoControl

            // Metronom
            Button {
                metronome.bpm = scaledBPM
                metronome.pattern = detail.grundrhythmus   // Song-Grundrhythmus (nil ⇒ Backbeat)
                metronome.toggle()
            } label: {
                Image(systemName: "metronome\(metronome.isRunning ? ".fill" : "")")
                    .font(.system(size: 30))
                    .foregroundColor(metronome.isRunning ? .accentColor : .primary)
            }
            .disabled((selectedSong?.bpm ?? 0) <= 0)

            // Play/Pause (Play-along)
            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .disabled(!player.hasTrack)
        }
        .padding(.horizontal, 24)
    }

    /// Playback- & Metronom-Tempo ändern; Mitte tippen = zurück auf „Normal".
    private var tempoControl: some View {
        HStack(spacing: 4) {
            Image(systemName: "speedometer").font(.subheadline).foregroundColor(.secondary)
            Button { adjustTempo(-0.05) } label: { Image(systemName: "minus") }
                .buttonStyle(.bordered)
            Button { resetTempo() } label: {
                Text(practiceTempo == 1.0 ? "Normal" : "\(Int((practiceTempo * 100).rounded())) %")
                    .font(.caption).monospacedDigit().frame(minWidth: 58)
            }
            .buttonStyle(.bordered)
            Button { adjustTempo(0.05) } label: { Image(systemName: "plus") }
                .buttonStyle(.bordered)
        }
    }

    private var scaledBPM: Int { Int((Double(selectedSong?.bpm ?? 120) * practiceTempo).rounded()) }

    private func adjustTempo(_ d: Double) {
        practiceTempo = min(1.2, max(0.5, ((practiceTempo + d) * 20).rounded() / 20))
        applyTempo()
    }

    private func resetTempo() { practiceTempo = 1.0; applyTempo() }

    private func applyTempo() {
        player.setBaseRate(Float(practiceTempo))
        if metronome.isRunning {
            metronome.bpm = scaledBPM
            metronome.reload()
        }
    }

    // Unten rechts (80 % Höhe): Lyrics (Karaoke) oder Takt-Raster
    private var mainArea: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mainTab) {
                Text("Lyrics").tag(MainTab.lyrics)
                Text("Takte").tag(MainTab.bars)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24).padding(.vertical, 8)
            Divider()
            Group {
                if selectedSong != nil {
                    switch mainTab {
                    case .lyrics: LyricsView(vm: detail, player: player)
                    case .bars:   SongGridView(song: selectedSong!, vm: detail, player: player, store: markerStore)
                    }
                } else {
                    Text("Song auswählen").foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Helpers

    private func selectSong(_ song: CatalogSong?) {
        guard let song else { return }
        selectedID = song.id
        practiceTempo = 1.0          // neues Lied → Tempo zurück auf Normal
        metronome.stop()
        player.load(path: song.playalongPath)
        Task { await detail.load(songID: song.id) }
    }
}

/// Hauptbereich: Parts (mit echten Namen/Längen) × Takte (Spalten).
/// Aktiver Takt wird im Playmodus aus der Timeline (t_start) hervorgehoben,
/// das Raster scrollt automatisch mit. Stellen lassen sich markieren und loopen.
private struct SongGridView: View {
    let song: CatalogSong
    @ObservedObject var vm: SongDetailViewModel
    @ObservedObject var player: SongPlayer
    @ObservedObject var store: PracticeMarkerStore
    @StateObject private var speed = SpeedTrainer()

    @State private var markMode = false
    @State private var pendingStart: Int?
    @State private var pendingEnd: Int?
    @State private var pendingReason: PracticeReason?
    @State private var pendingMode: PracticeMode = .loop
    @State private var showReasonSheet = false
    @State private var markerToDelete: PracticeMarker?

    /// Gesamtzahl Takte (DB → Timeline → Snippets als Fallback).
    private var maxBar: Int {
        vm.totalBars ?? vm.bars.last?.barNum ?? song.snippetBars.last ?? 0
    }

    /// Echte Parts mit ihren Taktbereichen (aus song_parts_public).
    private var sections: [(name: String, bars: [Int])] {
        guard !vm.parts.isEmpty, maxBar > 0 else { return [] }
        let sorted = vm.parts.sorted { $0.startBar < $1.startBar }
        return sorted.enumerated().compactMap { i, part in
            let start = max(1, part.startBar)
            let end = i + 1 < sorted.count ? sorted[i + 1].startBar - 1 : maxBar
            guard end >= start else { return nil }
            return (part.name, Array(start...end))
        }
    }

    private var songMarkers: [PracticeMarker] { store.markers(forSong: song.id) }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            if player.isLooping || speed.countInBeat > 0 {
                Divider()
                SpeedTrainerBar(trainer: speed, isLooping: player.isLooping)
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }
            Divider()
            content
            if !songMarkers.isEmpty {
                markerList
            }
        }
        .sheet(isPresented: $showReasonSheet) { reasonSheet }
        .task(id: song.id) { speed.stop(); await store.load(songID: song.id) }
        .onDisappear { speed.stop() }
    }

    // MARK: - Steuerleiste

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                markMode.toggle()
                pendingStart = nil; pendingEnd = nil
            } label: {
                Label(markMode ? "Abbrechen" : "Stelle markieren",
                      systemImage: markMode ? "xmark.circle" : "plus.circle.fill")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(markMode ? .red : .accentColor)
            if markMode {
                Text(pendingStart == nil ? "Ersten Takt antippen" : "Letzten Takt antippen (Start: \(pendingStart!))")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if player.isLooping {
                Button { player.clearLoop(); speed.stop() } label: {
                    Label("Loop aus", systemImage: "stop.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
            }
            Button {
                Task {
                    await vm.load(songID: song.id, force: true)
                    await store.load(songID: song.id)
                }
            } label: {
                Image(systemName: "arrow.clockwise").font(.subheadline)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: - Raster

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sections.isEmpty && maxBar == 0 {
            Text("Keine Takt-Struktur verfügbar.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if sections.isEmpty {
                            partSection(name: "Takte", bars: Array(1...maxBar))
                        } else {
                            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                                partSection(name: section.name, bars: section.bars)
                            }
                        }
                    }
                    .padding(20)
                }
                .onChange(of: vm.activeBarNum) { _, bar in
                    guard let bar else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo("gbar-\(bar)", anchor: .center)
                    }
                }
            }
        }
    }

    private func partSection(name: String, bars: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(name.uppercased())
                    .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                Text("· \(bars.count) Takte")
                    .font(.caption2).foregroundColor(.secondary)
            }
            FlowLayout(spacing: 8) {
                ForEach(bars, id: \.self) { bar in
                    barCell(bar)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func barCell(_ bar: Int) -> some View {
        let isActive = vm.activeBarNum == bar
        let isPending = markMode && pendingStart == bar
        let markerColor = songMarkers.first { $0.contains(bar: bar) }?.reason.color
        let strokeColor: Color = isPending ? .orange : (markerColor ?? (isActive ? .accentColor : Color(.separator)))
        return Text("\(bar)")
            .font(.callout).monospacedDigit()
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.accentColor : Color(.secondarySystemBackground))
            )
            .foregroundColor(isActive ? .white : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(strokeColor, lineWidth: (isPending || markerColor != nil) ? 2.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                let starts = songMarkers.filter { $0.startBar == bar }
                if !starts.isEmpty {
                    HStack(spacing: 1) {
                        ForEach(starts) { m in
                            Image(systemName: m.reason.systemImage)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(m.reason.color))
                        }
                    }
                    // Mittelpunkt genau auf die obere rechte Ecke des Taktquadrats.
                    .offset(x: 9, y: -9)
                }
            }
            .id("gbar-\(bar)")
            .contentShape(Rectangle())
            .onTapGesture { tapBar(bar) }
            .animation(.easeInOut(duration: 0.12), value: isActive)
    }

    // MARK: - Marker-Liste

    private var markerList: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                Text("Markierte Stellen").font(.caption).fontWeight(.semibold)
                if store.syncError != nil {
                    Image(systemName: "icloud.slash").font(.caption2).foregroundColor(.secondary)
                    Text("offline – lokal gespeichert").font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(songMarkers) { marker in markerRow(marker) }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
            .frame(maxHeight: 150)
        }
        .background(Color(.secondarySystemBackground).opacity(0.4))
        .confirmationDialog(
            "Markierte Stelle löschen?",
            isPresented: Binding(get: { markerToDelete != nil }, set: { if !$0 { markerToDelete = nil } }),
            titleVisibility: .visible,
            presenting: markerToDelete
        ) { marker in
            Button("Löschen", role: .destructive) {
                Task { await store.remove(marker) }
                markerToDelete = nil
            }
            Button("Abbrechen", role: .cancel) { markerToDelete = nil }
        } message: { marker in
            Text("Takt \(marker.startBar)–\(marker.endBar) · \(marker.reason.label) wird unwiderruflich gelöscht.")
        }
    }

    private func markerRow(_ marker: PracticeMarker) -> some View {
        HStack(spacing: 10) {
            Image(systemName: marker.reason.systemImage).foregroundColor(marker.reason.color)
            VStack(alignment: .leading, spacing: 1) {
                Text("Takt \(marker.startBar)–\(marker.endBar)").font(.subheadline)
                HStack(spacing: 4) {
                    Text(marker.reason.label)
                    Image(systemName: marker.mode.systemImage)
                    Text(marker.mode.shortLabel)
                }
                .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button { loop(marker) } label: {
                Image(systemName: "repeat").font(.body)
            }
            .buttonStyle(.borderless)
            .disabled(!vm.hasTiming || !player.hasTrack)
            Button(role: .destructive) { markerToDelete = marker } label: {
                Image(systemName: "trash").font(.body)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
    }

    // MARK: - Grund-Auswahl

    /// Sinnvolle Vorbelegung des Übe-Modus je Grund.
    private func defaultMode(for reason: PracticeReason) -> PracticeMode {
        switch reason {
        case .shift, .notes:            return .context   // im Zusammenhang
        case .speed, .precision, .timing: return .loop    // im Loop
        case .other:                    return .loop
        }
    }

    private var reasonSheet: some View {
        NavigationStack {
            Form {
                Section("Grund") {
                    ForEach(PracticeReason.allCases) { reason in
                        Button {
                            pendingReason = reason
                            pendingMode = defaultMode(for: reason)   // sinnvoll vorbelegen
                        } label: {
                            HStack {
                                Label(reason.label, systemImage: reason.systemImage)
                                    .foregroundColor(.primary)
                                Spacer()
                                if pendingReason == reason {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
                if pendingReason != nil {
                    Section("Übe-Modus") {
                        Picker("Modus", selection: $pendingMode) {
                            ForEach(PracticeMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(pendingMode == .loop
                             ? "Loop der Stelle – erst langsam, dann schneller (Präzision)."
                             : "Mit Anlauf aus dem Teil davor – Übergang im Zusammenhang.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(reasonTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { finishMarking() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") { saveMarker() }.disabled(pendingReason == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var reasonTitle: String {
        guard let s = pendingStart, let e = pendingEnd else { return "Stelle markieren" }
        return "Takt \(min(s, e))–\(max(s, e))"
    }

    // MARK: - Aktionen

    private func tapBar(_ bar: Int) {
        if markMode {
            if pendingStart == nil {
                pendingStart = bar
            } else {
                pendingEnd = bar
                showReasonSheet = true
            }
        } else if let t = vm.startTime(forBar: bar) {
            player.seek(to: t)
        }
    }

    private func saveMarker() {
        if let s = pendingStart, let e = pendingEnd, let reason = pendingReason {
            let songID = song.id
            let mode = pendingMode
            Task { await store.add(songID: songID, startBar: s, endBar: e, reason: reason, mode: mode) }
        }
        finishMarking()
    }

    private func finishMarking() {
        showReasonSheet = false
        markMode = false
        pendingStart = nil
        pendingEnd = nil
        pendingReason = nil
        pendingMode = .loop
    }

    private func loop(_ marker: PracticeMarker) {
        // Im Zusammenhang + Lagenwechsel: 8 Takte Anlauf, 4 Takte Auslauf.
        // Sonst im Zusammenhang: 2 Takte Anlauf. Reiner Loop: exakt die Stelle.
        let combo = marker.mode == .context && marker.reason == .shift
        let leadBars = combo ? 8 : (marker.mode == .context ? 2 : 0)
        let trailBars = combo ? 4 : 0

        let startBar = max(1, marker.startBar - leadBars)
        let endBar = marker.endBar + trailBars
        guard let start = vm.startTime(forBar: startBar) ?? vm.startTime(forBar: marker.startBar) else { return }
        let end = vm.endTime(forBar: endBar) ?? vm.endTime(forBar: marker.endBar) ?? player.duration
        guard end > start else { return }
        // Einzähler + Tempo-/Präzisions-Steuerung (gleicher Baustein wie im Kapitel).
        speed.stop()
        speed.configure(player: player, bpm: song.bpm ?? 120)
        Task { @MainActor in
            await speed.countIn()
            player.playLoop(start: start, end: end,
                            progressive: speed.mode == .autoTime, startRate: speed.startRate)
            speed.loopStarted()
        }
    }
}

/// Einfaches Flow-Layout: ordnet Subviews zeilenweise und bricht bei Breite um.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    SongsView(source: .setlist)
}
