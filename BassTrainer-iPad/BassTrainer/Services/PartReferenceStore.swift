import Foundation

/// Verwaltet Referenzaufnahmen der Song-Teile: laden, hochladen (Storage +
/// `part_references`) und löschen. Pro User via RLS/auth.uid().
@MainActor
final class PartReferenceStore: ObservableObject {
    @Published private(set) var references: [PartReference] = []
    @Published var status: String?

    private let auth = SupabaseAuth.shared
    private let bucket = "references"

    /// Referenz für einen Teil (per Starttakt identifiziert), falls vorhanden.
    func reference(songID: String, startBar: Int) -> PartReference? {
        references.first { $0.songID == songID && $0.startBar == startBar }
    }

    func load(songID: String) async {
        do {
            let token = try await auth.token()
            let data = try await SupabaseConfig.authedData(
                method: "GET", path: "part_references",
                query: [URLQueryItem(name: "song_id", value: "eq.\(songID)"),
                        URLQueryItem(name: "select", value: "id,song_id,part_name,start_bar,end_bar,storage_path,sample_rate,duration_sec,envelope"),
                        URLQueryItem(name: "order", value: "start_bar.asc")],
                token: token)
            references = try JSONDecoder().decode([PartReference].self, from: data)
        } catch {
            // leise – Cache/leer
        }
    }

    /// Lädt eine gut bewertete Teil-Aufnahme als Referenz hoch (Storage + DB).
    func saveReference(songID: String, partName: String, startBar: Int, endBar: Int,
                       samples: [Float], sampleRate: Double, envelope: [Double]) async throws {
        status = "Lade Referenz hoch …"
        let token = try await auth.token()
        let uid = try await auth.userID()
        let path = "\(uid)/\(songID)/\(startBar).wav"
        let wav = WAVEncoder.encode(samples, sampleRate: sampleRate)
        try await SupabaseConfig.uploadObject(bucket: bucket, path: path, data: wav,
                                              contentType: "audio/wav", token: token)

        // Eigene Zeile dieses Teils ersetzen (Song+Starttakt), dann neu schreiben.
        try await SupabaseConfig.authedData(
            method: "DELETE", path: "part_references",
            query: [URLQueryItem(name: "song_id", value: "eq.\(songID)"),
                    URLQueryItem(name: "start_bar", value: "eq.\(startBar)")],
            token: token)

        struct Row: Encodable {
            let song_id: String; let part_name: String
            let start_bar: Int; let end_bar: Int
            let storage_path: String; let sample_rate: Double
            let duration_sec: Double; let envelope: [Double]
        }
        let dur = Double(samples.count) / sampleRate
        let body = try JSONEncoder().encode([Row(song_id: songID, part_name: partName,
                                                 start_bar: startBar, end_bar: endBar,
                                                 storage_path: path, sample_rate: sampleRate,
                                                 duration_sec: dur, envelope: envelope)])
        _ = try await SupabaseConfig.authedData(
            method: "POST", path: "part_references", body: body, token: token, prefer: "return=minimal")
        await load(songID: songID)
        status = "Referenz gespeichert"
    }

    func delete(_ ref: PartReference) async {
        do {
            let token = try await auth.token()
            try await SupabaseConfig.authedData(
                method: "DELETE", path: "part_references",
                query: [URLQueryItem(name: "id", value: "eq.\(ref.id)")],
                token: token)
            references.removeAll { $0.id == ref.id }
        } catch {
            status = "Löschen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Temporäre URL zum Anhören einer Referenz.
    func playbackURL(for ref: PartReference) async -> URL? {
        do {
            let token = try await auth.token()
            return try await SupabaseConfig.signedURL(bucket: bucket, path: ref.storagePath, expiresIn: 3600, token: token)
        } catch { return nil }
    }
}
