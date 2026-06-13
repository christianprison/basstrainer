import Foundation

/// Lädt Timeline/Lyrics eines Songs und bestimmt im Playmodus den aktiven Takt.
/// Timing kommt ausschließlich aus `song_timeline_public` (handgesetzte Marker) —
/// niemals aus BPM berechnet.
@MainActor
final class LyricsViewModel: ObservableObject {
    @Published private(set) var bars: [TimelineBar] = []   // nur bei synchronisierten Songs
    @Published private(set) var fallbackLyrics: String?    // lyrics_raw (statischer Fallback)
    @Published private(set) var isSynced = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var activeIndex: Int?          // Index in `bars`

    private var loadedSongID: String?

    /// Lädt die Daten für einen Song (idempotent pro Song-ID).
    func load(songID: String) async {
        guard songID != loadedSongID else { return }
        loadedSongID = songID
        isLoading = true
        error = nil
        bars = []
        fallbackLyrics = nil
        isSynced = false
        activeIndex = nil
        defer { isLoading = false }

        do {
            // 1) Timeline (Rückgrat). Leeres Ergebnis = Song ohne Timing → Fallback.
            let timeline: [TimelineBar] = try await SupabaseConfig.get(
                path: "song_timeline_public",
                query: [
                    URLQueryItem(name: "song_id", value: "eq.\(songID)"),
                    URLQueryItem(name: "order", value: "bar_num.asc"),
                ]
            )
            if !timeline.isEmpty {
                bars = timeline
                isSynced = true
                return
            }

            // 2) Statischer Fallback für Songs ohne Timing.
            let raw: [LyricsRawRow] = try await SupabaseConfig.get(
                path: "song_lyrics_public",
                query: [
                    URLQueryItem(name: "song_id", value: "eq.\(songID)"),
                    URLQueryItem(name: "select", value: "lyrics_raw,total_bars"),
                ]
            )
            fallbackLyrics = raw.first?.lyricsRaw
            isSynced = false
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

    /// Startzeit eines Takts (für Tap-to-Seek).
    func startTime(forBar barNum: Int) -> Double? {
        bars.first { $0.barNum == barNum }?.tStart
    }
}
