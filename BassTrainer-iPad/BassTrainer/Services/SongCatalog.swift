import Foundation

/// Verbindung zum zentralen Supabase-Katalog (Read-only).
/// Der anon/Publishable-Key ist browser-/client-safe (RLS erlaubt nur SELECT),
/// daher darf er im Client liegen. NIEMALS den service_role-Key einbetten.
enum SupabaseConfig {
    static let url = "https://ivkcvvjtwwfommsnxerv.supabase.co"

    // anon/Publishable-Key (browser-/client-safe, RLS erlaubt nur SELECT).
    static let anonKey = "sb_publishable_bS0KjYSEGa_CVEplXPC_ZA_gloEimqh"

    static var isConfigured: Bool { !anonKey.isEmpty }

    /// Öffentliche Audio-URL im public-Bucket `snippets`.
    static func publicAudioURL(for storagePath: String) -> URL? {
        let encoded = storagePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? storagePath
        return URL(string: "\(url)/storage/v1/object/public/snippets/\(encoded)")
    }
}

/// Lädt die aktuelle Setlist (View `setlist_public`) + Play-along-Tracks per PostgREST.
@MainActor
final class SongCatalog: ObservableObject {
    @Published var songs: [SetlistSong] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        guard SupabaseConfig.isConfigured else {
            error = "Supabase-Zugang noch nicht konfiguriert (anon-Key fehlt)."
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // 1) Aktuelle Setlist, sortiert nach pos.
            let rows: [SetlistRow] = try await fetch(
                path: "setlist_public",
                query: [
                    URLQueryItem(name: "select", value: "pos,song_id,name,artist,bpm,music_key,duration_sec"),
                    URLQueryItem(name: "order", value: "pos.asc"),
                ]
            )

            // 2) Play-along-Tracks (nur 43 von 51 Songs haben einen) → Map song_id → Pfad.
            let assets: [PlayalongRow] = try await fetch(
                path: "audio_assets",
                query: [
                    URLQueryItem(name: "select", value: "song_id,storage_path"),
                    URLQueryItem(name: "kind", value: "eq.playalong"),
                ]
            )
            let pathBySong = Dictionary(assets.map { ($0.songId, $0.storagePath) }, uniquingKeysWith: { first, _ in first })

            songs = rows.map { row in
                SetlistSong(
                    id: row.songId,
                    pos: row.pos,
                    name: row.name,
                    artist: row.artist,
                    bpm: row.bpm,
                    musicKey: row.musicKey,
                    durationSec: row.durationSec,
                    playalongPath: pathBySong[row.songId]
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Generischer read-only GET gegen PostgREST.
    private func fetch<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        var comps = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/\(path)")!
        comps.queryItems = query
        var req = URLRequest(url: comps.url!)
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw CatalogError.message("Keine Antwort vom Server.")
        }
        guard http.statusCode == 200 else {
            throw CatalogError.message("Server-Fehler (HTTP \(http.statusCode)).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    enum CatalogError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case let .message(m) = self { return m }; return nil }
    }
}
