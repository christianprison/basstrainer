import Foundation

/// Welche Song-Quelle eine Songs-Übung anzeigt.
enum SongSource {
    case setlist      // nur aktuelle Setlist (View setlist_public)
    case repertoire   // alle Songs (Tabelle songs)

    var title: String {
        switch self {
        case .setlist:    return "Aktuelle Setlist"
        case .repertoire: return "Repertoire"
        }
    }
}

/// Ein Song aus dem zentralen Katalog, angereichert um Play-along-Pfad + bekannte Takte.
struct CatalogSong: Identifiable {
    let id: String          // = song_id (text-PK)
    let pos: Int?           // Position in der Setlist (nil im Repertoire)
    let name: String
    let artist: String?
    let bpm: Int?
    let musicKey: String?
    let durationSec: Int?
    var playalongPath: String?
    var snippetBars: [Int]  // bekannte Taktnummern (aus per-Takt-Snippets), sortiert

    var hasPlayalong: Bool { playalongPath != nil }
}

// MARK: - PostgREST DTOs

/// Zeile aus `setlist_public`.
struct SetlistRow: Decodable {
    let pos: Int
    let songId: String
    let name: String
    let artist: String?
    let bpm: Int?
    let musicKey: String?
    let durationSec: Int?

    enum CodingKeys: String, CodingKey {
        case pos, name, artist, bpm
        case songId = "song_id"
        case musicKey = "music_key"
        case durationSec = "duration_sec"
    }
}

/// Zeile aus `songs` (Repertoire).
struct SongRow: Decodable {
    let id: String
    let name: String
    let artist: String?
    let bpm: Int?
    let musicKey: String?
    let durationSec: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, artist, bpm
        case musicKey = "music_key"
        case durationSec = "duration_sec"
    }
}

/// Eintrag aus `audio_assets`.
struct AudioAssetRow: Decodable {
    let songId: String
    let storagePath: String?
    let barNum: Int?

    enum CodingKeys: String, CodingKey {
        case songId = "song_id"
        case storagePath = "storage_path"
        case barNum = "bar_num"
    }
}
