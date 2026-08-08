import Foundation

/// Persönliche Song-Tipps aus Supabase (`song_tips`, privat pro User via RLS).
/// DB ist die Quelle der Wahrheit; lokaler Cache dient als Offline-Fallback.
@MainActor
final class SongTipStore: ObservableObject {
    @Published private(set) var tips: [PersonalTip] = []
    @Published var syncError: String?

    private let auth = SupabaseAuth.shared
    private let cacheKey = "songTips.cache.v1"

    init() { loadCache() }

    func tips(forSong songID: String) -> [PersonalTip] {
        tips.filter { $0.songID == songID }
    }

    /// Lädt die Tipps eines Songs frisch aus der DB (Cache bleibt bei Fehler erhalten).
    func load(songID: String) async {
        do {
            let token = try await auth.token()
            let data = try await SupabaseConfig.authedData(
                method: "GET",
                path: "song_tips",
                query: [
                    URLQueryItem(name: "song_id", value: "eq.\(songID)"),
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "order", value: "created_at.asc"),
                ],
                token: token
            )
            let rows = try JSONDecoder().decode([PersonalTip].self, from: data)
            tips.removeAll { $0.songID == songID }
            tips.append(contentsOf: rows)
            saveCache()
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Legt einen Tipp an (DB; bei Fehler lokal als Fallback).
    func add(songID: String, title: String?, text: String?, tab: [String]?) async {
        do {
            let token = try await auth.token()
            let payload = try JSONEncoder().encode(
                PersonalTipInsert(song_id: songID, title: title, text: text, tab: tab)
            )
            let data = try await SupabaseConfig.authedData(
                method: "POST", path: "song_tips", body: payload,
                token: token, prefer: "return=representation"
            )
            let created = try JSONDecoder().decode([PersonalTip].self, from: data)
            tips.append(contentsOf: created)
            saveCache()
            syncError = nil
        } catch {
            tips.append(PersonalTip(songID: songID, title: title, text: text, tab: tab))
            saveCache()
            syncError = error.localizedDescription
        }
    }

    /// Aktualisiert einen bestehenden Tipp.
    func update(_ tip: PersonalTip) async {
        // Lokal sofort spiegeln.
        if let i = tips.firstIndex(where: { $0.id == tip.id }) { tips[i] = tip }
        saveCache()
        do {
            let token = try await auth.token()
            let payload = try JSONEncoder().encode(
                PersonalTipUpdate(title: tip.title, text: tip.text, tab: tip.tab)
            )
            _ = try await SupabaseConfig.authedData(
                method: "PATCH", path: "song_tips",
                query: [URLQueryItem(name: "id", value: "eq.\(tip.id.uuidString)")],
                body: payload, token: token, prefer: "return=minimal"
            )
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Löscht einen Tipp (DB; lokal in jedem Fall).
    func remove(_ tip: PersonalTip) async {
        do {
            let token = try await auth.token()
            try await SupabaseConfig.authedData(
                method: "DELETE", path: "song_tips",
                query: [URLQueryItem(name: "id", value: "eq.\(tip.id.uuidString)")],
                token: token
            )
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
        tips.removeAll { $0.id == tip.id }
        saveCache()
    }

    // MARK: - Cache

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([PersonalTip].self, from: data) else { return }
        tips = decoded
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(tips) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}
