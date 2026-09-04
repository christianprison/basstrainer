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

    @State private var editing: PrepItem?
    @State private var adding = false
    @State private var launch: LaunchSong?
    @State private var loaded = false

    private struct LaunchSong: Identifiable { let id: String }

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
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .disabled(catalog.songs.isEmpty)
                }
            }
            .task { if !loaded { loaded = true; await reload() } }
            .sheet(isPresented: $adding) {
                PrepEditor(songs: catalog.songs, item: nil) { songID, type, note in
                    Task { await store.add(songID: songID, type: type, note: note, bandID: bandID) }
                }
            }
            .sheet(item: $editing) { item in
                PrepEditor(songs: catalog.songs, item: item) { songID, type, note in
                    var updated = item; updated.songID = songID; updated.type = type; updated.note = note
                    Task { await store.update(updated, bandID: bandID) }
                }
            }
            .fullScreenCover(item: $launch) { l in
                SongsView(source: .setlist, preselectID: l.id)
            }
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
            Text("Noch keine Bausteine. Füge oben mit + eigene hinzu – oder lade den vorbereiteten Startinhalt.")
                .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
            if store.hasSeed(bandID: bandID) {
                Button { Task { await store.seed(bandID: bandID) } } label: {
                    Label("Schwächen dieser Setlist laden", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
    }

    private func row(_ item: PrepItem) -> some View {
        Button { launch = LaunchSong(id: item.songID) } label: {
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
                Image(systemName: "play.circle").foregroundColor(.accentColor)
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
    let onSave: (_ songID: String, _ type: PrepType, _ note: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var songID: String
    @State private var type: PrepType
    @State private var note: String

    init(songs: [CatalogSong], item: PrepItem?,
         onSave: @escaping (_ songID: String, _ type: PrepType, _ note: String) -> Void) {
        self.songs = songs
        self.item = item
        self.onSave = onSave
        _songID = State(initialValue: item?.songID ?? songs.first?.id ?? "")
        _type = State(initialValue: item?.type ?? .start)
        _note = State(initialValue: item?.note ?? "")
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
                Section("Notiz") {
                    TextField("z. B. Anfang sicher treffen, Tim ansehen …", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(item == nil ? "Baustein hinzufügen" : "Baustein bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { onSave(songID, type, note); dismiss() }
                        .disabled(songID.isEmpty)
                }
            }
        }
    }
}

#Preview {
    GigPrepView()
}
