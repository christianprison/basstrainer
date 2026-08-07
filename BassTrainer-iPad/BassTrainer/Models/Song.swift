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
    var pick: String?       // aus songs.pick — enthält "🔻" wenn mit Plektrum gespielt

    var hasPlayalong: Bool { playalongPath != nil }

    /// Wird das Stück mit Pick/Plektrum gespielt? (Datenfeld enthält dann „🔻".)
    var playedWithPick: Bool { (pick ?? "").contains("🔻") }

    /// Zusatztext im pick-Feld ohne das Dreieck (z. B. „Harp C"), falls vorhanden.
    var pickAnnotation: String? {
        let rest = (pick ?? "").replacingOccurrences(of: "🔻", with: "")
            .trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
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

/// Zeile aus `songs` – nur für das Pick-Kennzeichen (in `setlist_public` fehlt es).
struct PickRow: Decodable {
    let id: String
    let pick: String?
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

// MARK: - Lyrics / Timeline

/// Ein Takt aus `song_timeline_public` — Rückgrat der Karaoke-Hervorhebung.
struct TimelineBar: Identifiable, Decodable {
    let barNum: Int
    let tStart: Double
    let tEnd: Double?       // null nur beim letzten Takt → Songende = Audiodauer
    let partName: String?
    let lyrics: String?
    let instrumental: Bool

    var id: Int { barNum }
    var text: String { (lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasText: Bool { !instrumental && !text.isEmpty }

    enum CodingKeys: String, CodingKey {
        case barNum = "bar_num"
        case tStart = "t_start"
        case tEnd = "t_end"
        case partName = "part_name"
        case lyrics, instrumental
    }
}

/// Statischer Fallback aus `song_lyrics_public` (für Songs ohne Timing).
struct LyricsRawRow: Decodable {
    let lyricsRaw: String?
    let totalBars: Int?

    enum CodingKeys: String, CodingKey {
        case lyricsRaw = "lyrics_raw"
        case totalBars = "total_bars"
    }
}

/// Section/Part aus `song_parts_public` — echte Part-Namen + Starttakte.
struct SongPart: Decodable, Identifiable {
    let startBar: Int
    let name: String

    var id: Int { startBar }

    enum CodingKeys: String, CodingKey {
        case startBar = "start_bar"
        case name = "part_name"
    }
}
