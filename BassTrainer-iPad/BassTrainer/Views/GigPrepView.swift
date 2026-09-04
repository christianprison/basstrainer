import SwiftUI

/// Auftritts-Vorbereitung: individuell zusammenstellbare Übungs-Bausteine pro
/// Song der aktuellen Setlist. Jeder Baustein hat einen Typ (Anfang, Loop+Tempo,
/// Passage, Merk-Karte) und eine Notiz; jeder zeigt automatisch den nächsten
/// Song im Set. Persistiert pro User in Supabase – wiederverwendbar pro Gig.
struct GigPrepView: View {
    @StateObject private var store = PrepStore()
    @StateObject private var catalog = SongCatalog(source: .setlist)
    @AppStorage("selectedBandID") private var bandID = ""
    @Environment(\.dismiss) private var dismiss

    @StateObject private var markerStore = PracticeMarkerStore()
    @State private var editing: PrepItem?
    @State private var adding = false
    @State private var launch: LaunchSong?
    @State private var loaded = false
    @State private var importInfo: String?

    private struct LaunchSong: Identifiable {
        let songID: String
        let start: Int?
        let end: Int?
        var id: String { "\(songID)-\(start ?? -1)-\(end ?? -1)" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !loaded && store.items.isEmpty && catalog.songs.isEmpty {
                    ProgressView("Lade Vorbereitung …").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .navigationTitle("Auftritts-Vorbereitung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Menü", systemImage: "chevron.left") }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { adding = true } label: { Label("Baustein hinzufügen", systemImage: "plus") }
                        Button { Task { await importMarkers() } } label: {
                            Label("Markierte Stellen übernehmen", systemImage: "mappin.and.ellipse")
                        }
                        if store.hasSeed(bandID: bandID) {
                            Button { Task { await store.seed(bandID: bandID) } } label: {
                                Label("Startinhalt laden", systemImage: "sparkles")
                            }
                        }
                    } label: { Image(systemName: "plus") }
                    .disabled(catalog.songs.isEmpty)
                }
            }
            .task { if !loaded { loaded = true; await reload() } }
            .sheet(isPresented: $adding) {
                PrepEditor(songs: catalog.songs, item: nil) { songID, type, note, s, e in
                    Task { await store.add(songID: songID, type: type, note: note, bandID: bandID, startBar: s, endBar: e) }
                }
            }
            .sheet(item: $editing) { item in
                PrepEditor(songs: catalog.songs, item: item) { songID, type, note, s, e in
                    var updated = item
                    updated.songID = songID; updated.type = type; updated.note = note
                    updated.startBar = s; updated.endBar = e
                    Task { await store.update(updated, bandID: bandID) }
                }
            }
            .fullScreenCover(item: $launch) { l in
                let bars: (start: Int, end: Int)? = (l.start != nil && l.end != nil) ? (l.start!, l.end!) : nil
                SongsView(source: .setlist, preselectID: l.songID, focused: true, autoLoopBars: bars)
            }
            .alert("Markierte Stellen", isPresented: Binding(get: { importInfo != nil }, set: { if !$0 { importInfo = nil } })) {
                Button("OK", role: .cancel) { importInfo = nil }
            } message: { Text(importInfo ?? "") }
        }
    }

    private var list: some View {
        List {
            if store.items.isEmpty {
                Section { emptyState }
            } else {
                Section {
                    ForEach(store.items) { item in row(item) }
                        .onDelete { idx in
                            let toDelete = idx.map { store.items[$0] }
                            Task { for it in toDelete { await store.delete(it, bandID: bandID) } }
                        }
                        .onMove { from, to in Task { await store.move(from: from, to: to, bandID: bandID) } }
                } header: {
                    Text("\(store.items.count) Bausteine · in Set-Reihenfolge sortierbar").textCase(nil)
                } footer: {
                    if let s = store.status { Text(s) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.rectangle.portrait").font(.system(size: 40)).foregroundColor(.secondary)
            Text("Noch keine Bausteine. Übernimm deine markierten Stellen, lade den Startinhalt – oder füge oben mit + eigene hinzu.")
                .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button { Task { await importMarkers() } } label: {
                Label("Markierte Stellen übernehmen", systemImage: "mappin.and.ellipse")
            }
            .buttonStyle(.borderedProminent)
            if store.hasSeed(bandID: bandID) {
                Button { Task { await store.seed(bandID: bandID) } } label: {
                    Label("Schwächen dieser Setlist laden", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
    }

    private func row(_ item: PrepItem) -> some View {
        Button { launch = LaunchSong(songID: item.songID, start: item.startBar, end: item.endBar) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.type.systemImage)
                    .font(.title3).foregroundColor(.accentColor).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(songName(item.songID)).font(.headline).lineLimit(1)
                        Text(item.type.label).font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundColor(.accentColor)
                        if let b = item.bars {
                            Text("Takt \(b.start)–\(b.end)").font(.caption2).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                .foregroundColor(.secondary)
                        }
                    }
                    if !item.note.isEmpty {
                        Text(item.note).font(.caption).foregroundColor(.secondary)
                    }
                    if let next = nextSong(item.songID) {
                        Label("danach: \(next)", systemImage: "arrow.turn.down.right")
                            .font(.caption2).foregroundColor(.secondary)
                    } else {
                        Label("letzter Song im Set", systemImage: "flag.checkered")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: item.bars != nil ? "repeat.circle" : "play.circle").foregroundColor(.accentColor)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await store.delete(item, bandID: bandID) }
            } label: { Label("Löschen", systemImage: "trash") }
            Button { editing = item } label: { Label("Bearbeiten", systemImage: "pencil") }.tint(.blue)
        }
    }

    private func reload() async {
        await catalog.load(bandID: bandID)
        await store.load(bandID: bandID)
    }

    private func importMarkers() async {
        await markerStore.loadAll()
        let setIDs = Set(catalog.songs.map { $0.id })
        let n = await store.importMarkers(markerStore.markers, songIDs: setIDs, bandID: bandID)
        importInfo = n > 0 ? "\(n) markierte Stelle(n) als Baustein übernommen." : "Keine neuen markierten Stellen gefunden."
    }

    private func songName(_ id: String) -> String {
        catalog.songs.first { $0.id == id }?.name ?? "Unbekannter Song"
    }

    private func nextSong(_ id: String) -> String? {
        guard let i = catalog.songs.firstIndex(where: { $0.id == id }), i + 1 < catalog.songs.count else { return nil }
        return catalog.songs[i + 1].name
    }
}

// MARK: - Editor

private struct PrepEditor: View {
    let songs: [CatalogSong]
    let item: PrepItem?
    let onSave: (_ songID: String, _ type: PrepType, _ note: String, _ startBar: Int?, _ endBar: Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var songID: String
    @State private var type: PrepType
    @State private var note: String
    @State private var bindToBars: Bool
    @State private var startBar: Int
    @State private var endBar: Int

    init(songs: [CatalogSong], item: PrepItem?,
         onSave: @escaping (_ songID: String, _ type: PrepType, _ note: String, _ startBar: Int?, _ endBar: Int?) -> Void) {
        self.songs = songs
        self.item = item
        self.onSave = onSave
        _songID = State(initialValue: item?.songID ?? songs.first?.id ?? "")
        _type = State(initialValue: item?.type ?? .start)
        _note = State(initialValue: item?.note ?? "")
        _bindToBars = State(initialValue: item?.bars != nil)
        _startBar = State(initialValue: item?.startBar ?? 1)
        _endBar = State(initialValue: item?.endBar ?? 4)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Song") {
                    Picker("Song", selection: $songID) {
                        ForEach(songs) { s in Text(s.name).tag(s.id) }
                    }
                }
                Section("Typ") {
                    Picker("Typ", selection: $type) {
                        ForEach(PrepType.allCases) { t in Label(t.label, systemImage: t.systemImage).tag(t) }
                    }
                    .pickerStyle(.inline)
                }
                Section("Notiz (was üben?)") {
                    TextField("z. B. Anfang sicher treffen, Tim ansehen …", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Toggle("An Taktstelle binden", isOn: $bindToBars)
                    if bindToBars {
                        Stepper("Von Takt \(startBar)", value: $startBar, in: 1...400)
                        Stepper("Bis Takt \(max(startBar, endBar))", value: $endBar, in: startBar...400)
                    }
                } header: {
                    Text("Passage (optional)")
                } footer: {
                    Text("Gebunden startet Antippen den Loop genau dieser Takte (mit Speed-Trainer). Am einfachsten über Markierte Stellen übernehmen.")
                }
            }
            .navigationTitle(item == nil ? "Baustein hinzufügen" : "Baustein bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let s = bindToBars ? startBar : nil
                        let e = bindToBars ? max(startBar, endBar) : nil
                        onSave(songID, type, note, s, e)
                        dismiss()
                    }
                    .disabled(songID.isEmpty)
                }
            }
        }
    }
}

#Preview {
    GigPrepView()
}
