import Foundation

/// Ein Audio-Asset aus `audio_assets` (Supabase).
struct AudioAsset: Decodable {
    let kind: String          // "playalong" | "snippet"
    let storagePath: String
    let barNum: Int?

    enum CodingKeys: String, CodingKey {
        case kind
        case storagePath = "storage_path"
        case barNum = "bar_num"
    }
}

/// Ein Song aus dem zentralen Katalog (Supabase `songs` + eingebettete `audio_assets`).
struct Song: Identifiable, Decodable {
    let id: String
    let name: String
    let artist: String?
    let bpm: Int?
    let musicKey: String?
    let duration: String?
    let audioAssets: [AudioAsset]

    /// Pfad des Full-Song-Play-along-Tracks (falls vorhanden).
    var playalongPath: String? {
        audioAssets.first { $0.kind == "playalong" }?.storagePath
    }

    var hasPlayalong: Bool { playalongPath != nil }

    enum CodingKeys: String, CodingKey {
        case id, name, artist, bpm, duration
        case musicKey = "music_key"
        case audioAssets = "audio_assets"
    }
}
