import Foundation

/// Kalibrierte Eingabe-Latenz (ms) zwischen hörbarem Klick und erkanntem
/// Anschlag. Persistiert lokal (UserDefaults, sofort verfügbar) **und** in
/// Supabase (`user_calibration`, pro User via auth.uid()).
///
/// Wird von den Präzisionsübungen (Timing-Bewertung) und der Songanfang-
/// Aufnahme (Beat-Quantisierung) genutzt, um die systematische Latenz
/// herauszurechnen: gemessene Onset-Zeit − Latenz = beabsichtigte Zeit.
@MainActor
final class CalibrationStore: ObservableObject {
    static let shared = CalibrationStore()

    private let auth = SupabaseAuth.shared
    private let key = "inputLatencyMs"
    private var didLoad = false

    @Published private(set) var latencyMs: Double

    private init() {
        latencyMs = UserDefaults.standard.double(forKey: key)
    }

    /// Latenz in Sekunden – von Onset-Zeiten abzuziehen.
    var latencySeconds: Double { latencyMs / 1000.0 }

    private func setLocal(_ ms: Double) {
        latencyMs = ms
        UserDefaults.standard.set(ms, forKey: key)
    }

    private struct Row: Codable { let latency_ms: Double }

    /// Einmalig pro Sitzung aus der DB nachladen (lokaler Wert bleibt bei Fehler).
    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        await load()
    }

    func load() async {
        do {
            let token = try await auth.token()
            let data = try await SupabaseConfig.authedData(
                method: "GET", path: "user_calibration",
                query: [URLQueryItem(name: "select", value: "latency_ms")],
                token: token)
            if let row = try JSONDecoder().decode([Row].self, from: data).first {
                setLocal(row.latency_ms)
            }
        } catch {
            // offline/leer: lokal gespeicherten Wert behalten
        }
    }

    /// Wert lokal setzen und in Supabase schreiben (eigene Zeile ersetzen).
    /// RLS begrenzt DELETE/INSERT auf die eigene user_id.
    func save(_ ms: Double) async throws {
        setLocal(ms)
        let token = try await auth.token()
        try await SupabaseConfig.authedData(
            method: "DELETE", path: "user_calibration",
            query: [URLQueryItem(name: "user_id", value: "not.is.null")], token: token)
        let body = try JSONEncoder().encode([Row(latency_ms: ms)])
        _ = try await SupabaseConfig.authedData(
            method: "POST", path: "user_calibration",
            body: body, token: token, prefer: "return=minimal")
    }
}
