import Foundation

/// Persistiert die Auftritts-Vorbereitung (Bausteine) pro User und Band in
/// Supabase (`prep_items`, RLS über auth.uid()). Speichern = Ersetzen der
/// eigenen Zeilen einer Band (DELETE + POST).
@MainActor
final class PrepStore: ObservableObject {
    @Published private(set) var items: [PrepItem] = []
    @Published var status: String?

    private let auth = SupabaseAuth.shared

    private struct Row: Codable {
        let id: String
        let band_id: String
        let song_id: String
        let type: String
        let note: String
        let ord: Int
    }

    func load(bandID: String) async {
        guard !bandID.isEmpty else { items = []; return }
        do {
            let token = try await auth.token()
            let data = try await SupabaseConfig.authedData(
                method: "GET", path: "prep_items",
                query: [URLQueryItem(name: "band_id", value: "eq.\(bandID)"),
                        URLQueryItem(name: "select", value: "id,song_id,type,note,ord"),
                        URLQueryItem(name: "order", value: "ord.asc")],
                token: token)
            items = try JSONDecoder().decode([PrepItem].self, from: data)
        } catch {
            // leise: lokale Liste bleibt, Nutzer sieht keinen Start-Toast
        }
    }

    func save(bandID: String) async {
        guard !bandID.isEmpty else { return }
        status = "Speichere …"
        do {
            let token = try await auth.token()
            try await SupabaseConfig.authedData(
                method: "DELETE", path: "prep_items",
                query: [URLQueryItem(name: "band_id", value: "eq.\(bandID)")],
                token: token)
            let rows = items.map { Row(id: $0.id, band_id: bandID, song_id: $0.songID,
                                       type: $0.type.rawValue, note: $0.note, ord: $0.ord) }
            if !rows.isEmpty {
                let body = try JSONEncoder().encode(rows)
                _ = try await SupabaseConfig.authedData(
                    method: "POST", path: "prep_items",
                    body: body, token: token, prefer: "return=minimal")
            }
            status = "Gespeichert (\(rows.count))"
        } catch {
            status = "Fehler: \(error.localizedDescription)"
        }
    }

    // MARK: Bearbeiten

    func add(songID: String, type: PrepType, note: String, bandID: String) async {
        let ord = (items.map { $0.ord }.max() ?? 0) + 1
        items.append(PrepItem(id: UUID().uuidString, songID: songID, type: type, note: note, ord: ord))
        await save(bandID: bandID)
    }

    func update(_ item: PrepItem, bandID: String) async {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
        await save(bandID: bandID)
    }

    func delete(_ item: PrepItem, bandID: String) async {
        items.removeAll { $0.id == item.id }
        await save(bandID: bandID)
    }

    func move(from: IndexSet, to: Int, bandID: String) async {
        items.move(fromOffsets: from, toOffset: to)
        for (i, _) in items.enumerated() { items[i].ord = i }
        await save(bandID: bandID)
    }

    // MARK: Startinhalt

    /// Ob für diese Band ein vordefinierter Startinhalt existiert.
    func hasSeed(bandID: String) -> Bool { bandID == "the_pact" }

    /// Fügt die aktuell besprochenen Schwächen (The Pact) als Bausteine hinzu.
    func seed(bandID: String) async {
        guard bandID == "the_pact" else { return }
        let seed: [(String, PrepType, String)] = [
            ("CC9FBm", .start,   "Anfang sicher treffen"),
            ("CC9FBm", .loop,    "Tempo steigern – bin noch nicht schnell genug"),
            ("CC9FBm", .cue,     "Insgesamt Sicherheit – oft genug durchspielen"),
            ("BKpY4X", .section, "Strophe: neue Lage sicher greifen"),
            ("hR5CDW", .section, "Endton sauber treffen"),
            ("5D6dZO", .cue,     "Tim vorher ansehen – er ändert die Hihat, bevor ich anfange"),
            ("HDX1IN", .start,   "Anfang – ersten Ton treffen"),
            ("pVmkRc", .loop,    "Letzter Chorus: Bassline über 2 Saiten/Finger – Loop mit steigendem Tempo"),
            ("Lnql7n", .cue,     "Anfang NICHT mit She Hates Me verwechseln"),
            ("RED66i", .cue,     "Anfang NICHT mit Creep verwechseln"),
            ("fwA4K7", .start,   "Anfang"),
            ("SQfqPy", .start,   "Anfang"),
            ("Pol09a", .start,   "Refrain als Soundcheck – merken, wie er anfängt"),
            ("Wa1bpl", .start,   "Anfang"),
        ]
        let base = (items.map { $0.ord }.max() ?? -1) + 1
        for (i, s) in seed.enumerated() {
            items.append(PrepItem(id: UUID().uuidString, songID: s.0, type: s.1, note: s.2, ord: base + i))
        }
        await save(bandID: bandID)
    }
}
