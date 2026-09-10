import Foundation

/// Referenzaufnahme eines Song-Teils: die gut bewertete eigene Bass-Aufnahme
/// dieses Parts. Audio liegt in Supabase Storage, Metadaten in `part_references`.
/// Dient später als Maßstab (Phase 2: automatischer Vergleich neuer Versuche).
struct PartReference: Identifiable, Codable, Equatable {
    var id: String
    var songID: String
    var partName: String
    var startBar: Int
    var endBar: Int
    var storagePath: String
    var sampleRate: Double
    var durationSec: Double
    var envelope: [Double]      // grob heruntergerechnete Lautstärke-Hüllkurve (für Phase 2)

    enum CodingKeys: String, CodingKey {
        case id
        case songID = "song_id"
        case partName = "part_name"
        case startBar = "start_bar"
        case endBar = "end_bar"
        case storagePath = "storage_path"
        case sampleRate = "sample_rate"
        case durationSec = "duration_sec"
        case envelope
    }

    init(id: String, songID: String, partName: String, startBar: Int, endBar: Int,
         storagePath: String, sampleRate: Double, durationSec: Double, envelope: [Double]) {
        self.id = id; self.songID = songID; self.partName = partName
        self.startBar = startBar; self.endBar = endBar; self.storagePath = storagePath
        self.sampleRate = sampleRate; self.durationSec = durationSec; self.envelope = envelope
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        songID = try c.decode(String.self, forKey: .songID)
        partName = (try? c.decode(String.self, forKey: .partName)) ?? ""
        startBar = (try? c.decode(Int.self, forKey: .startBar)) ?? 0
        endBar = (try? c.decode(Int.self, forKey: .endBar)) ?? 0
        storagePath = (try? c.decode(String.self, forKey: .storagePath)) ?? ""
        sampleRate = (try? c.decode(Double.self, forKey: .sampleRate)) ?? 48000
        durationSec = (try? c.decode(Double.self, forKey: .durationSec)) ?? 0
        envelope = (try? c.decode([Double].self, forKey: .envelope)) ?? []
    }
}
