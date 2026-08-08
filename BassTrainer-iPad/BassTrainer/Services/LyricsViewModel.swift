import Foundation

/// Lädt Timeline + Parts + statische Lyrics eines Songs und bestimmt im
/// Playmodus den aktiven Takt. Wird von Lyrics-Ansicht UND Takt-Raster genutzt.
/// Timing kommt ausschließlich aus `song_timeline_public` (handgesetzte Marker) —
/// niemals aus BPM berechnet.
@MainActor
final class SongDetailViewModel: ObservableObject {
    @Published private(set) var bars: [TimelineBar] = []   // Timeline (leer = nicht synchronisiert)
    @Published private(set) var parts: [SongPart] = []     // echte Parts (Name + Starttakt)
    @Published private(set) var totalBars: Int?            // Gesamtzahl Takte
    @Published private(set) var fallbackLyrics: String?    // lyrics_raw (statischer Fallback)
    @Published private(set) var isSynced = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var activeIndex: Int?          // Index in `bars`
    /// Pro Song hinterlegter Grundrhythmus (BD/SD-Positionen in Vierteln).
    /// nil = kein Muster hinterlegt ⇒ Standard-Backbeat.
    @Published private(set) var grundrhythmus: (kick: [Double], snare: [Double])?
    /// Pro Song hinterlegte Tipps (Text + saitige Bass-Tabs).
    @Published private(set) var tips: [SongTip] = []

    private var loadedSongID: String?

    /// Zeile aus `song_detail_lighting` mit projiziertem `detail->grundrhythmus` + `detail->tips`.
    private struct GrundrhythmusRow: Decodable {
        let grundrhythmus: GrundrhythmusData?
        let tips: [SongTip]?
    }
    private struct GrundrhythmusData: Decodable {
        let kick: [Double]?
        let snare: [Double]?
    }

    /// Lädt alle Detail-Daten für einen Song (idempotent pro Song-ID).
    /// `force = true` erzwingt ein Neuladen (z. B. nach DB-Änderung).
    func load(songID: String, force: Bool = false) async {
        if !force && songID == loadedSongID { return }
        loadedSongID = songID
        isLoading = true
        error = nil
        bars = []
        parts = []
        totalBars = nil
        fallbackLyrics = nil
        isSynced = false
        activeIndex = nil
        grundrhythmus = nil
        tips = []
        defer { isLoading = false }

        let idFilter = URLQueryItem(name: "song_id", value: "eq.\(songID)")
        do {
            async let timelineReq: [TimelineBar] = SupabaseConfig.get(
                path: "song_timeline_public",
                query: [idFilter, URLQueryItem(name: "order", value: "bar_num.asc")]
            )
            async let partsReq: [SongPart] = SupabaseConfig.get(
                path: "song_parts_public",
                query: [idFilter, URLQueryItem(name: "order", value: "start_bar.asc")]
            )
            async let lyricsReq: [LyricsRawRow] = SupabaseConfig.get(
                path: "song_lyrics_public",
                query: [idFilter, URLQueryItem(name: "select", value: "lyrics_raw,total_bars")]
            )
            async let grooveReq: [GrundrhythmusRow] = SupabaseConfig.get(
                path: "song_detail_lighting",
                query: [idFilter,
                        URLQueryItem(name: "select", value: "grundrhythmus:detail->grundrhythmus,tips:detail->tips")]
            )

            let timeline = try await timelineReq
            let partList = (try? await partsReq) ?? []          // best effort
            let lyrics = (try? await lyricsReq) ?? []
            let groove = (try? await grooveReq) ?? []

            bars = timeline
            parts = partList
            fallbackLyrics = lyrics.first?.lyricsRaw
            totalBars = lyrics.first?.totalBars ?? timeline.last?.barNum
            isSynced = !timeline.isEmpty
            grundrhythmus = Self.parseGroove(groove.first?.grundrhythmus)
            tips = (groove.first?.tips ?? []).filter { $0.hasContent }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Wandelt die DB-Rohdaten in ein Muster um. Liefert nil, wenn kein Muster
    /// hinterlegt ist (null) oder BD und SD beide leer sind ⇒ Standard-Backbeat.
    private static func parseGroove(_ data: GrundrhythmusData?) -> (kick: [Double], snare: [Double])? {
        guard let data else { return nil }
        let kick = data.kick ?? []
        let snare = data.snare ?? []
        if kick.isEmpty && snare.isEmpty { return nil }
        return (kick, snare)
    }

    /// Aktiver Takt = letzter Takt mit `t_start <= currentTime` (binäre Suche).
    func update(currentTime: Double) {
        guard isSynced, !bars.isEmpty else { return }
        var lo = 0
        var hi = bars.count - 1
        var found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if bars[mid].tStart <= currentTime {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        let idx = found >= 0 ? found : nil
        if idx != activeIndex { activeIndex = idx }
    }

    /// Aktive Taktnummer (für Highlight im Raster).
    var activeBarNum: Int? {
        guard let i = activeIndex, bars.indices.contains(i) else { return nil }
        return bars[i].barNum
    }

    /// Startzeit eines Takts (für Tap-to-Seek / Loop-Start).
    func startTime(forBar barNum: Int) -> Double? {
        bars.first { $0.barNum == barNum }?.tStart
    }

    /// Endzeit eines Takts (Loop-Ende). Bei null `t_end` die Startzeit des
    /// nächsten Takts; gibt es keinen, liefert nil (Aufrufer nutzt Audiodauer).
    func endTime(forBar barNum: Int) -> Double? {
        guard let bar = bars.first(where: { $0.barNum == barNum }) else { return nil }
        if let end = bar.tEnd { return end }
        return bars.first(where: { $0.barNum > barNum })?.tStart
    }

    /// Gibt es synchronisiertes Timing (für Loop nötig)?
    var hasTiming: Bool { isSynced && !bars.isEmpty }
}
