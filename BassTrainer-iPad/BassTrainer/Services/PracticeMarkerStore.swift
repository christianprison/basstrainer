import Foundation

/// Übe-Marker aus Supabase (`practice_markers`, privat pro User via RLS).
/// DB ist die Quelle der Wahrheit; lokaler Cache dient als Offline-Fallback.
@MainActor
final class PracticeMarkerStore: ObservableObject {
    @Published private(set) var markers: [PracticeMarker] = []
    @Published var syncError: String?

    private let auth = SupabaseAuth.shared
    private let cacheKey = "practiceMarkers.cache.v2"
    private let legacyKey = "practiceMarkers.v1"
    private var didMigrateLegacy = false

    init() { loadCache() }

    /// Marker eines Songs, nach Starttakt sortiert.
    func markers(forSong songID: String) -> [PracticeMarker] {
        markers.filter { $0.songID == songID }.sorted { $0.startBar < $1.startBar }
    }

    /// Lädt die Marker eines Songs frisch aus der DB (Cache bleibt bei Fehler erhalten).
    func load(songID: String) async {
        await migrateLegacyIfNeeded()
        do {
            let token = try await auth.token()
            let data = try await SupabaseConfig.authedData(
                method: "GET",
                path: "practice_markers",
                query: [
                    URLQueryItem(name: "song_id", value: "eq.\(songID)"),
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "order", value: "start_bar.asc"),
                ],
                token: token
            )
            let rows = try JSONDecoder().decode([PracticeMarker].self, from: data)
            markers.removeAll { $0.songID == songID }
            markers.append(contentsOf: rows)
            saveCache()
            syncError = nil
        } catch {
            syncError = error.localizedDescription   // Cache weiterverwenden
        }
    }

    /// Legt einen Marker an (DB; bei Fehler lokal als Fallback).
    func add(songID: String, startBar: Int, endBar: Int, reason: PracticeReason, mode: PracticeMode, note: String? = nil) async {
        let s = min(startBar, endBar)
        let e = max(startBar, endBar)
        do {
            let token = try await auth.token()
            let payload = try JSONEncoder().encode(
                PracticeMarkerInsert(song_id: songID, start_bar: s, end_bar: e, reason: reason.rawValue, mode: mode.rawValue, note: note)
            )
            let data = try await SupabaseConfig.authedData(
                method: "POST",
                path: "practice_markers",
                body: payload,
                token: token,
                prefer: "return=representation"
            )
            let created = try JSONDecoder().decode([PracticeMarker].self, from: data)
            markers.append(contentsOf: created)
            saveCache()
            syncError = nil
        } catch {
            markers.append(PracticeMarker(songID: songID, startBar: s, endBar: e, reason: reason, mode: mode, note: note))
            saveCache()
            syncError = error.localizedDescription
        }
    }

    /// Löscht einen Marker (DB; lokal in jedem Fall).
    func remove(_ marker: PracticeMarker) async {
        do {
            let token = try await auth.token()
            try await SupabaseConfig.authedData(
                method: "DELETE",
                path: "practice_markers",
                query: [URLQueryItem(name: "id", value: "eq.\(marker.id.uuidString)")],
                token: token
            )
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
        markers.removeAll { $0.id == marker.id }
        saveCache()
    }

    // MARK: - Migration alter lokaler Marker

    private func migrateLegacyIfNeeded() async {
        guard !didMigrateLegacy else { return }
        guard let data = UserDefaults.standard.data(forKey: legacyKey),
              let legacy = try? JSONDecoder().decode([LegacyMarker].self, from: data),
              !legacy.isEmpty else {
            didMigrateLegacy = true
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return
        }
        guard let token = try? await auth.token() else { return }  // später erneut versuchen
        for m in legacy {
            let payload = try? JSONEncoder().encode(
                PracticeMarkerInsert(song_id: m.songID, start_bar: m.startBar, end_bar: m.endBar, reason: m.reason.rawValue, mode: PracticeMode.loop.rawValue, note: nil)
            )
            if let payload {
                _ = try? await SupabaseConfig.authedData(
                    method: "POST", path: "practice_markers", body: payload, token: token, prefer: "return=minimal"
                )
            }
        }
        didMigrateLegacy = true
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    /// Altes lokales Format (vor DB-Anbindung): default-CodingKeys.
    private struct LegacyMarker: Decodable {
        let songID: String
        let startBar: Int
        let endBar: Int
        let reason: PracticeReason
    }

    // MARK: - Lokaler Cache

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([PracticeMarker].self, from: data) else { return }
        markers = decoded
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(markers) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}
