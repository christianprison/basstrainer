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

            // Metronom
            Button {
                metronome.bpm = selectedSong?.bpm ?? 120
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

    @State private var markMode = false
    @State private var pendingStart: Int?
    @State private var pendingEnd: Int?
    @State private var showReasonSheet = false

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
            Divider()
            content
            if !songMarkers.isEmpty {
                markerList
            }
        }
        .sheet(isPresented: $showReasonSheet) { reasonSheet }
    }

    // MARK: - Steuerleiste

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                markMode.toggle()
                pendingStart = nil; pendingEnd = nil
            } label: {
                Label(markMode ? "Abbrechen" : "Stelle markieren",
                      systemImage: markMode ? "xmark.circle" : "plus.circle")
                    .font(.subheadline)
            }
            if markMode {
                Text(pendingStart == nil ? "Ersten Takt antippen" : "Letzten Takt antippen (Start: \(pendingStart!))")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if player.isLooping {
                Button { player.clearLoop() } label: {
                    Label("Loop aus", systemImage: "repeat.circle.fill").font(.subheadline)
                }
                .foregroundColor(.accentColor)
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
            .id("gbar-\(bar)")
            .contentShape(Rectangle())
            .onTapGesture { tapBar(bar) }
            .animation(.easeInOut(duration: 0.12), value: isActive)
    }

    // MARK: - Marker-Liste

    private var markerList: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("Markierte Stellen").font(.caption).fontWeight(.semibold)
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
    }

    private func markerRow(_ marker: PracticeMarker) -> some View {
        HStack(spacing: 10) {
            Image(systemName: marker.reason.systemImage).foregroundColor(marker.reason.color)
            VStack(alignment: .leading, spacing: 1) {
                Text("Takt \(marker.startBar)–\(marker.endBar)").font(.subheadline)
                Text(marker.reason.label).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button { loop(marker) } label: {
                Image(systemName: "repeat").font(.body)
            }
            .buttonStyle(.borderless)
            .disabled(!vm.hasTiming || !player.hasTrack)
            Button(role: .destructive) { store.remove(marker) } label: {
                Image(systemName: "trash").font(.body)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
    }

    // MARK: - Grund-Auswahl

    private var reasonSheet: some View {
        NavigationStack {
            List(PracticeReason.allCases) { reason in
                Button {
                    if let s = pendingStart, let e = pendingEnd {
                        store.add(songID: song.id, startBar: s, endBar: e, reason: reason)
                    }
                    finishMarking()
                } label: {
                    Label(reason.label, systemImage: reason.systemImage)
                        .foregroundColor(.primary)
                }
            }
            .navigationTitle(reasonTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { finishMarking() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var reasonTitle: String {
        guard let s = pendingStart, let e = pendingEnd else { return "Grund wählen" }
        return "Takt \(min(s, e))–\(max(s, e)): Grund"
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

    private func finishMarking() {
        showReasonSheet = false
        markMode = false
        pendingStart = nil
        pendingEnd = nil
    }

    private func loop(_ marker: PracticeMarker) {
        guard let start = vm.startTime(forBar: marker.startBar) else { return }
        let end = vm.endTime(forBar: marker.endBar) ?? player.duration
        guard end > start else { return }
        player.playLoop(start: start, end: end)
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
