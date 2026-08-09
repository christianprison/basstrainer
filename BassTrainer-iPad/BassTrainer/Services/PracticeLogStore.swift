import Foundation

/// Ein Übungs-Log-Eintrag (Tabelle `practice_log`, privat pro User via RLS).
struct PracticeLogEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    let category: String        // Art der Übung (z. B. "Orientierung")
    let detail: String?         // optionaler Zusatz (z. B. Song/Interval)
    let startedAt: String       // ISO8601-Zeitstempel
    let durationSec: Int
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, category, detail, note
        case startedAt = "started_at"
        case durationSec = "duration_sec"
    }

    init(id: UUID = UUID(), category: String, detail: String?, startedAt: String, durationSec: Int, note: String? = nil) {
        self.id = id; self.category = category; self.detail = detail
        self.startedAt = startedAt; self.durationSec = durationSec; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        category = (try? c.decode(String.self, forKey: .category)) ?? "Übung"
        detail = try? c.decode(String.self, forKey: .detail)
        startedAt = (try? c.decode(String.self, forKey: .startedAt)) ?? ""
        durationSec = (try? c.decode(Int.self, forKey: .durationSec)) ?? 0
        note = try? c.decode(String.self, forKey: .note)
    }

    /// Tag (yyyy-MM-dd) für die Gruppierung.
    var day: String { startedAt.split(separator: "T").first.map(String.init) ?? startedAt }
    /// Uhrzeit HH:mm.
    var timeHM: String {
        guard let t = startedAt.split(separator: "T").dropFirst().first else { return "" }
        return String(t.prefix(5))
    }
    var minutes: Int { max(1, Int((Double(durationSec) / 60.0).rounded())) }
}

private struct PracticeLogInsert: Encodable {
    let category: String
    let detail: String?
    let started_at: String
    let duration_sec: Int
    let note: String?
}

/// Übungs-Log: hält automatisch fest, welche Übung wann/ wie lange lief.
/// Quelle der Wahrheit ist Supabase; lokaler Cache als Offline-Fallback.
@MainActor
final class PracticeLogStore: ObservableObject {
    static let shared = PracticeLogStore()

    @Published private(set) var entries: [PracticeLogEntry] = []
    @Published var syncError: String?

    private let auth = SupabaseAuth.shared
    private let cacheKey = "practiceLog.cache.v1"
    private let minSeconds = 20            // kürzere „Besuche" nicht loggen
    private let iso = ISO8601DateFormatter()
    private var pending: (category: String, detail: String?, start: Date)?

    private init() { loadCache() }

    // MARK: - Automatisches Session-Logging

    func begin(category: String, detail: String?) {
        if pending != nil { end() }
        pending = (category, detail, Date())
    }

    func end() {
        guard let p = pending else { return }
        pending = nil
        let dur = Int(Date().timeIntervalSince(p.start))
        guard dur >= minSeconds else { return }
        let started = iso.string(from: p.start)
        Task { await add(category: p.category, detail: p.detail, startedAt: started, durationSec: dur) }
    }

    // MARK: - CRUD

    func load() async {
        do {
            let token = try await auth.token()
            let data = try await SupabaseConfig.authedData(
                method: "GET", path: "practice_log",
                query: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "order", value: "started_at.desc"),
                    URLQueryItem(name: "limit", value: "500"),
                ],
                token: token
            )
            entries = try JSONDecoder().decode([PracticeLogEntry].self, from: data)
            saveCache()
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func add(category: String, detail: String?, startedAt: String, durationSec: Int) async {
        do {
            let token = try await auth.token()
            let payload = try JSONEncoder().encode(
                PracticeLogInsert(category: category, detail: detail, started_at: startedAt,
                                  duration_sec: durationSec, note: nil)
            )
            let data = try await SupabaseConfig.authedData(
                method: "POST", path: "practice_log", body: payload,
                token: token, prefer: "return=representation"
            )
            let created = try JSONDecoder().decode([PracticeLogEntry].self, from: data)
            entries.insert(contentsOf: created, at: 0)
            saveCache()
            syncError = nil
        } catch {
            entries.insert(PracticeLogEntry(category: category, detail: detail, startedAt: startedAt, durationSec: durationSec), at: 0)
            saveCache()
            syncError = error.localizedDescription
        }
    }

    func remove(_ entry: PracticeLogEntry) async {
        do {
            let token = try await auth.token()
            try await SupabaseConfig.authedData(
                method: "DELETE", path: "practice_log",
                query: [URLQueryItem(name: "id", value: "eq.\(entry.id.uuidString)")],
                token: token
            )
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
        entries.removeAll { $0.id == entry.id }
        saveCache()
    }

    // MARK: - Cache

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([PracticeLogEntry].self, from: data) else { return }
        entries = decoded
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}
