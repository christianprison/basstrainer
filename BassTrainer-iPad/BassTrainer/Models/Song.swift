import Foundation

/// Ein Song aus der aktuellen Setlist (View `setlist_public`, sortiert nach `pos`),
/// angereichert um den optionalen Play-along-Pfad aus `audio_assets`.
struct SetlistSong: Identifiable {
    let id: String          // = song_id (text-PK)
    let pos: Int
    let name: String
    let artist: String?
    let bpm: Int?
    let musicKey: String?
    let durationSec: Int?
    var playalongPath: String?

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

/// Play-along-Eintrag aus `audio_assets` (kind = 'playalong').
struct PlayalongRow: Decodable {
    let songId: String
    let storagePath: String

    enum CodingKeys: String, CodingKey {
        case songId = "song_id"
        case storagePath = "storage_path"
    }
}
