import SwiftUI

/// "Aktuelle Setlist" — lädt die geordnete Setlist aus Supabase und bietet Play-along.
struct SongsView: View {
    @StateObject private var catalog = SongCatalog()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if catalog.isLoading {
                    ProgressView("Lade Setlist …")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = catalog.error {
                    errorView(error)
                } else if catalog.songs.isEmpty {
                    Text("Setlist ist leer.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    songList
                }
            }
            .navigationTitle("Aktuelle Setlist")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Menü", systemImage: "chevron.left") }
                }
            }
        }
        .task { if catalog.songs.isEmpty { await catalog.load() } }
    }

    private var songList: some View {
        List(catalog.songs) { song in
            if song.hasPlayalong {
                NavigationLink(value: song.id) {
                    SongRow(song: song)
                }
            } else {
                SongRow(song: song).opacity(0.5)
            }
        }
        .navigationDestination(for: String.self) { id in
            if let song = catalog.songs.first(where: { $0.id == id }) {
                SongPlayerView(song: song)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundColor(.secondary)
            Text("Konnte Setlist nicht laden").font(.headline)
            Text(message).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("Erneut versuchen") { Task { await catalog.load() } }.buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SongRow: View {
    let song: SetlistSong
    var body: some View {
        HStack(spacing: 12) {
            Text("\(song.pos)")
                .font(.callout).monospacedDigit().foregroundColor(.secondary)
                .frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.name).font(.headline)
                if let artist = song.artist { Text(artist).font(.subheadline).foregroundColor(.secondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let bpm = song.bpm { Text("\(bpm) BPM").font(.caption).monospacedDigit() }
                if let key = song.musicKey { Text(key).font(.caption2).foregroundColor(.secondary) }
            }
            if song.hasPlayalong {
                Image(systemName: "play.circle.fill").foregroundColor(.accentColor).font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SongsView()
}
