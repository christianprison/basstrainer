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

    private var loadedSongID: String?

    /// Lädt alle Detail-Daten für einen Song (idempotent pro Song-ID).
    func load(songID: String) async {
        guard songID != loadedSongID else { return }
        loadedSongID = songID
        isLoading = true
        error = nil
        bars = []
        parts = []
        totalBars = nil
        fallbackLyrics = nil
        isSynced = false
        activeIndex = nil
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

            let timeline = try await timelineReq
            let partList = (try? await partsReq) ?? []          // best effort
            let lyrics = (try? await lyricsReq) ?? []

            bars = timeline
            parts = partList
            fallbackLyrics = lyrics.first?.lyricsRaw
            totalBars = lyrics.first?.totalBars ?? timeline.last?.barNum
            isSynced = !timeline.isEmpty
        } catch {
            self.error = error.localizedDescription
        }
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

    /// Startzeit eines Takts (für Tap-to-Seek).
    func startTime(forBar barNum: Int) -> Double? {
        bars.first { $0.barNum == barNum }?.tStart
    }
}
