import Foundation

/// Verbindung zum zentralen Supabase-Katalog (Read-only).
/// Der anon/Publishable-Key ist browser-/client-safe (RLS erlaubt nur SELECT),
/// daher darf er im Client liegen. NIEMALS den service_role-Key einbetten.
enum SupabaseConfig {
    static let url = "https://ivkcvvjtwwfommsnxerv.supabase.co"

    // TODO: anon/Publishable-Key vom Projekt-Owner eintragen (sb_publishable_… oder Legacy anon).
    static let anonKey = ""

    static var isConfigured: Bool { !anonKey.isEmpty }

    /// Öffentliche Audio-URL im public-Bucket `snippets`.
    static func publicAudioURL(for storagePath: String) -> URL? {
        let encoded = storagePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? storagePath
        return URL(string: "\(url)/storage/v1/object/public/snippets/\(encoded)")
    }
}

/// Lädt den Song-Katalog per PostgREST.
@MainActor
final class SongCatalog: ObservableObject {
    @Published var songs: [Song] = []
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

        var comps = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/songs")!
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,name,artist,bpm,music_key,duration,audio_assets(kind,storage_path,bar_num)"),
            URLQueryItem(name: "order", value: "name.asc"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                error = "Keine Antwort vom Server."
                return
            }
            guard http.statusCode == 200 else {
                error = "Server-Fehler (HTTP \(http.statusCode))."
                return
            }
            songs = try JSONDecoder().decode([Song].self, from: data)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
