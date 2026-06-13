import SwiftUI

/// Lyrics im Apple-Music-/Karaoke-Stil. Bei synchronisierten Songs wird die
/// aktive Zeile hervorgehoben und automatisch zentriert gescrollt; sonst
/// statischer Fallback aus `lyrics_raw`.
struct LyricsView: View {
    let song: CatalogSong
    @ObservedObject var player: SongPlayer
    @StateObject private var vm = LyricsViewModel()

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.error {
                message("Lyrics nicht geladen", error)
            } else if vm.isSynced {
                syncedLyrics
            } else if let raw = vm.fallbackLyrics, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                staticLyrics(raw)
            } else {
                message("Keine Lyrics", "Für diesen Song sind keine Texte hinterlegt.")
            }
        }
        .task(id: song.id) { await vm.load(songID: song.id) }
        .onChange(of: player.progress) { _, t in vm.update(currentTime: t) }
    }

    // MARK: - Synchronisiert (Karaoke)

    private var syncedLyrics: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        switch row {
                        case let .header(name, _):
                            Text(name.uppercased())
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.top, 18)
                                .id(row.id)
                        case let .line(bar):
                            lineView(bar)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .top) {
                if instrumentalActive {
                    Label("Instrumental", systemImage: "music.note")
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundColor(.accentColor)
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
            .onChange(of: vm.activeIndex) { _, _ in
                guard let id = scrollTargetID else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func lineView(_ bar: TimelineBar) -> some View {
        let active = activeBar?.barNum == bar.barNum
        return Text(bar.text)
            .font(.title3)
            .fontWeight(active ? .bold : .regular)
            .foregroundColor(.primary)
            .opacity(active ? 1.0 : 0.55)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .id("bar-\(bar.barNum)")
            .onTapGesture {
                if let t = vm.startTime(forBar: bar.barNum) { player.seek(to: t) }
            }
            .animation(.easeInOut(duration: 0.15), value: active)
    }

    // MARK: - Statischer Fallback

    private func staticLyrics(_ raw: String) -> some View {
        VStack(spacing: 0) {
            Label("nicht synchronisiert", systemImage: "text.alignleft")
                .font(.caption2).foregroundColor(.secondary)
                .padding(.vertical, 6)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(raw.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                            Text(trimmed.dropFirst().dropLast().uppercased())
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(.secondary).padding(.top, 14)
                        } else if !trimmed.isEmpty {
                            Text(line).font(.title3)
                        } else {
                            Color.clear.frame(height: 6)
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func message(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ableitungen

    private enum Row: Identifiable {
        case header(String, id: String)
        case line(TimelineBar)
        var id: String {
            switch self {
            case let .header(_, id): return id
            case let .line(bar): return "bar-\(bar.barNum)"
            }
        }
    }

    /// Anzeigezeilen: Part-Header bei Wechsel + Textzeilen (keine Leer-/Instrumentaltakte).
    private var rows: [Row] {
        var out: [Row] = []
        var lastPart: String?
        for bar in vm.bars {
            if let p = bar.partName, p != lastPart {
                out.append(.header(p, id: "header-\(bar.barNum)"))
                lastPart = p
            }
            if bar.hasText { out.append(.line(bar)) }
        }
        return out
    }

    private var activeBar: TimelineBar? {
        guard let i = vm.activeIndex, vm.bars.indices.contains(i) else { return nil }
        return vm.bars[i]
    }

    private var instrumentalActive: Bool {
        guard let active = activeBar else { return false }
        return !active.hasText
    }

    private var scrollTargetID: String? {
        guard let active = activeBar else { return rows.first?.id }
        if active.hasText { return "bar-\(active.barNum)" }
        // Instrumental: zur nächsten Textzeile scrollen (sonst zur vorherigen).
        if let next = vm.bars.first(where: { $0.barNum >= active.barNum && $0.hasText }) {
            return "bar-\(next.barNum)"
        }
        if let prev = vm.bars.last(where: { $0.barNum <= active.barNum && $0.hasText }) {
            return "bar-\(prev.barNum)"
        }
        return nil
    }
}
