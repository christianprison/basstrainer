import Foundation

/// Liest Song-Anfänge (öffentlich) und schreibt sie als Kurator (DELETE+POST).
@MainActor
final class IntroRepository: ObservableObject {
    private let auth = SupabaseAuth.shared

    /// Öffentlich lesbare Anfänge eines Songs.
    func load(songID: String) async throws -> [IntroNote] {
        try await SupabaseConfig.get(
            path: "song_intro_public",
            query: [
                URLQueryItem(name: "song_id", value: "eq.\(songID)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "idx.asc"),
            ]
        )
    }

    /// Speichern = Ersetzen: erst alle Töne des Songs löschen, dann neu schreiben.
    /// Nur Kuratoren dürfen schreiben (RLS); sonst `RESTError.forbidden`.
    func save(songID: String, notes: [IntroNote]) async throws {
        let token = try await auth.token()

        try await SupabaseConfig.authedData(
            method: "DELETE",
            path: "song_intros",
            query: [URLQueryItem(name: "song_id", value: "eq.\(songID)")],
            token: token
        )

        guard !notes.isEmpty else { return }

        let payload = notes.enumerated().map { i, n in
            IntroNoteWrite(
                song_id: songID,
                idx: i + 1,
                midi: n.midi,
                beat: n.beat,
                duration_beats: n.durationBeats,
                string: n.string,
                fret: n.fret,
                note_name: n.noteName ?? BassIntro.noteName(forMidi: n.midi)
            )
        }
        let body = try JSONEncoder().encode(payload)
        try await SupabaseConfig.authedData(
            method: "POST",
            path: "song_intros",
            body: body,
            token: token,
            prefer: "return=minimal"
        )
    }

    /// Song-IDs, für die Anfänge hinterlegt sind (für die Abruf-Übung).
    func songIDsWithIntro() async throws -> [String] {
        struct Row: Decodable { let song_id: String }
        let rows: [Row] = try await SupabaseConfig.get(
            path: "song_intro_public",
            query: [URLQueryItem(name: "select", value: "song_id")]
        )
        return Array(Set(rows.map { $0.song_id }))
    }

    /// Eigene uid für den Kurator-Modus.
    func currentUserID() async throws -> String {
        try await auth.userID()
    }
}
