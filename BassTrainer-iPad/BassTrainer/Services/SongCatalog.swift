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

    enum RESTError: LocalizedError {
        case notConfigured
        case forbidden
        case message(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Supabase-Zugang noch nicht konfiguriert (anon-Key fehlt)."
            case .forbidden:     return "Nicht als Kurator freigeschaltet."
            case let .message(m): return m
            }
        }
    }

    /// Generischer read-only GET gegen PostgREST.
    static func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        guard isConfigured else { throw RESTError.notConfigured }
        var comps = URLComponents(string: "\(url)/rest/v1/\(path)")!
        comps.queryItems = query
        var req = URLRequest(url: comps.url!)
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw RESTError.message("Keine Antwort vom Server.")
        }
        guard http.statusCode == 200 else {
            throw RESTError.message("Server-Fehler (HTTP \(http.statusCode)).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Authentifizierter REST-Request (Schreiben/Lesen mit User-JWT).
    /// Liefert die Antwort-Daten (kann leer sein, z. B. bei DELETE).
    @discardableResult
    static func authedData(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        token: String,
        prefer: String? = nil
    ) async throws -> Data {
        var comps = URLComponents(string: "\(url)/rest/v1/\(path)")!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if code == 403 { throw RESTError.forbidden }
        guard (200...299).contains(code) else {
            let body = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = body.isEmpty ? "" : " – \(body.prefix(300))"
            throw RESTError.message("Server-Fehler (HTTP \(code))\(detail)")
        }
        return data
    }
}

/// Lädt eine Song-Quelle (Setlist oder Repertoire) + Play-along-Tracks + Takt-Snippets.
@MainActor
final class SongCatalog: ObservableObject {
    let source: SongSource

    @Published var songs: [CatalogSong] = []
    @Published var isLoading = false
    @Published var error: String?

    init(source: SongSource) {
        self.source = source
    }

    func load() async {
        guard SupabaseConfig.isConfigured else {
            error = "Supabase-Zugang noch nicht konfiguriert (anon-Key fehlt)."
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // 1) Audio-Assets einmal holen → Play-along-Pfad + bekannte Takte je Song.
            //    Snippet = ein Takt (hat bar_num), Play-along = Full-Song (bar_num null).
            let assets: [AudioAssetRow] = try await fetch(
                path: "audio_assets",
                query: [URLQueryItem(name: "select", value: "song_id,storage_path,bar_num")]
            )
            var playalong: [String: String] = [:]
            var bars: [String: [Int]] = [:]
            for a in assets {
                if let bar = a.barNum {
                    bars[a.songId, default: []].append(bar)
                } else if let path = a.storagePath, playalong[a.songId] == nil {
                    playalong[a.songId] = path
                }
            }
            for key in bars.keys { bars[key]?.sort() }

            // 2) Song-Liste je nach Quelle.
            switch source {
            case .setlist:
                let rows: [SetlistRow] = try await fetch(
                    path: "setlist_public",
                    query: [
                        URLQueryItem(name: "select", value: "pos,song_id,name,artist,bpm,music_key,duration_sec"),
                        URLQueryItem(name: "order", value: "pos.asc"),
                    ]
                )
                songs = rows.map { r in
                    CatalogSong(id: r.songId, pos: r.pos, name: r.name, artist: r.artist,
                                bpm: r.bpm, musicKey: r.musicKey, durationSec: r.durationSec,
                                playalongPath: playalong[r.songId], snippetBars: bars[r.songId] ?? [])
                }
            case .repertoire:
                let rows: [SongRow] = try await fetch(
                    path: "songs",
                    query: [
                        URLQueryItem(name: "select", value: "id,name,artist,bpm,music_key,duration_sec"),
                        URLQueryItem(name: "order", value: "name.asc"),
                    ]
                )
                songs = rows.map { r in
                    CatalogSong(id: r.id, pos: nil, name: r.name, artist: r.artist,
                                bpm: r.bpm, musicKey: r.musicKey, durationSec: r.durationSec,
                                playalongPath: playalong[r.id], snippetBars: bars[r.id] ?? [])
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Read-only GET gegen PostgREST (delegiert an den gemeinsamen Helfer).
    private func fetch<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        try await SupabaseConfig.get(path: path, query: query)
    }
}
