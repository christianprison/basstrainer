import SwiftUI

/// Übungs-Log: zeigt automatisch erfasste Übungseinheiten, nach Tag gruppiert.
/// Grundlage für den später geplanten KI-Übungsplan.
struct PracticeLogView: View {
    @ObservedObject private var store = PracticeLogStore.shared
    @Environment(\.dismiss) private var dismiss

    /// Einträge gruppiert nach Tag (absteigend).
    private var days: [(day: String, items: [PracticeLogEntry])] {
        let groups = Dictionary(grouping: store.entries) { $0.day }
        return groups.keys.sorted(by: >).map { key in
            (key, groups[key]!.sorted { $0.startedAt > $1.startedAt })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(days, id: \.day) { group in
                            Section {
                                ForEach(group.items) { entry in row(entry) }
                                    .onDelete { idx in delete(group.items, idx) }
                            } header: {
                                dayHeader(group.day, minutes: group.items.reduce(0) { $0 + $1.minutes })
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Übungs-Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Menü", systemImage: "chevron.left") }
                }
            }
            .task { await store.load() }
        }
    }

    private func row(_ entry: PracticeLogEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.timeHM).font(.caption).monospacedDigit().foregroundColor(.secondary).frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.category).font(.subheadline)
                if let d = entry.detail, !d.isEmpty {
                    Text(d).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            Text("\(entry.minutes) min").font(.caption).foregroundColor(.secondary).monospacedDigit()
        }
    }

    private func dayHeader(_ day: String, minutes: Int) -> some View {
        HStack {
            Text(formatted(day)).textCase(nil)
            Spacer()
            Text("\(minutes) min").textCase(nil)
        }
        .font(.caption).foregroundColor(.secondary)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed").font(.system(size: 36)).foregroundColor(.secondary)
            Text("Noch keine Übungen erfasst").font(.headline)
            Text("Sobald du eine Übung startest, wird sie hier automatisch mit Dauer festgehalten.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(_ items: [PracticeLogEntry], _ idx: IndexSet) {
        for i in idx { let e = items[i]; Task { await store.remove(e) } }
    }

    /// "2026-08-07" → "07.08.2026" (rein String-basiert, robust).
    private func formatted(_ day: String) -> String {
        let p = day.split(separator: "-")
        guard p.count == 3 else { return day }
        return "\(p[2]).\(p[1]).\(p[0])"
    }
}

extension View {
    /// Erfasst das Öffnen/Schließen dieser Ansicht automatisch im Übungs-Log,
    /// sofern `active` (nur echte Übungen).
    func logPractice(_ category: String, active: Bool, detail: String? = nil) -> some View {
        self
            .onAppear { if active { PracticeLogStore.shared.begin(category: category, detail: detail) } }
            .onDisappear { if active { PracticeLogStore.shared.end() } }
    }
}
