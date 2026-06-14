import Foundation

/// Persistenter Speicher für Übe-Marker (lokal, UserDefaults/JSON).
/// Bewusst NICHT in Supabase – die DB ist read-only und die Marker sind privat.
@MainActor
final class PracticeMarkerStore: ObservableObject {
    @Published private(set) var markers: [PracticeMarker] = []

    private let key = "practiceMarkers.v1"

    init() { load() }

    /// Marker eines Songs, nach Starttakt sortiert.
    func markers(forSong songID: String) -> [PracticeMarker] {
        markers.filter { $0.songID == songID }.sorted { $0.startBar < $1.startBar }
    }

    func add(songID: String, startBar: Int, endBar: Int, reason: PracticeReason) {
        let s = min(startBar, endBar)
        let e = max(startBar, endBar)
        markers.append(PracticeMarker(songID: songID, startBar: s, endBar: e, reason: reason))
        save()
    }

    func remove(_ marker: PracticeMarker) {
        markers.removeAll { $0.id == marker.id }
        save()
    }

    // MARK: - Persistenz

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PracticeMarker].self, from: data) else { return }
        markers = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(markers) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
