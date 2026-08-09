import SwiftUI

/// Pentatonic Shapes: zeigt die Dur-/Moll-Pentatonik eines Grundtons auf dem
/// Griffbrett. Grundton in Pink, übrige Skalentöne in Blau. Über die Lage 1–5
/// lässt sich je eine Shape (Box) isolieren; „Alle" zeigt die ganze Skala.
struct PentatonicView: View {
    @StateObject private var vm = PentatonicViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            header
            HStack(spacing: 16) {
                scalePicker
                rootMenu
                Spacer()
            }
            positionPicker
            caption
            // 2× herangezoomt, horizontal scrollbar → Buchstaben überlappen nicht.
            ScrollView(.horizontal, showsIndicators: true) {
                let boardWidth: CGFloat = 1800
                FretboardView(
                    currentPosition: nil,
                    isPlaying: false,
                    levelColor: .accentColor,
                    markers: vm.scaleMarkers,
                    markerColor: Color(red: 0.20, green: 0.50, blue: 0.95),
                    rootMarkers: vm.rootMarkers,
                    rootColor: Color(red: 0.90, green: 0.20, blue: 0.55),
                    markerScale: 0.78
                )
                .frame(width: boardWidth, height: boardWidth * 332.0 / 4019.0)
            }
            legend
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.systemBackground))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Label("Menü", systemImage: "chevron.left").font(.subheadline.weight(.semibold))
            }
            Spacer()
            Text("Pentatonic Shapes").font(.headline)
            Spacer()
            Label("Menü", systemImage: "chevron.left").font(.subheadline.weight(.semibold)).opacity(0)
        }
    }

    private var scalePicker: some View {
        Picker("Tongeschlecht", selection: $vm.scale) {
            ForEach(PentatonicViewModel.Scale.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)
    }

    private var rootMenu: some View {
        Menu {
            ForEach(NoteName.allNotes) { n in
                Button(n.rawValue) { vm.root = n }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Grundton").font(.caption).foregroundColor(.secondary)
                Text(vm.root.rawValue).font(.headline).monospaced()
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
        }
    }

    private var positionPicker: some View {
        Picker("Lage", selection: $vm.position) {
            Text("Alle").tag(0)
            ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var caption: some View {
        Text(vm.relativeHint)
            .font(.caption).foregroundColor(.secondary)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendDot(Color(red: 0.90, green: 0.20, blue: 0.55), "Grundton")
            legendDot(Color(red: 0.20, green: 0.50, blue: 0.95), "Skalenton")
        }
        .font(.caption)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(text).foregroundColor(.secondary)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class PentatonicViewModel: ObservableObject {
    enum Scale: String, CaseIterable, Identifiable {
        case major, minor
        var id: String { rawValue }
        var label: String { self == .major ? "Dur" : "Moll" }
        /// Pentatonik-Intervalle in Halbtönen ab Grundton.
        var intervals: [Int] { self == .major ? [0, 2, 4, 7, 9] : [0, 3, 5, 7, 10] }
    }

    @Published var scale: Scale = .minor
    @Published var root: NoteName = .a
    @Published var position: Int = 0     // 0 = alle, 1…5 = Shape

    private let genMax = 24
    private let allLagenMax = 15

    private var rootPC: Int { NoteName.allNotes.firstIndex(of: root) ?? 0 }
    private var scaleSet: Set<Int> { Set(scale.intervals.map { (rootPC + $0) % 12 }) }
    private func pc(_ n: NoteName) -> Int { NoteName.allNotes.firstIndex(of: n) ?? 0 }

    /// Tiefster Bund (0…11) des Grundtons auf der E-Saite – Anker der Lagen.
    private var rootFretLow: Int {
        let pat = BassString.e.notePattern
        for f in 0..<12 where pat[f] == root { return f }
        return 0
    }

    /// Bund-Fenster einer Shape (nil = „Alle").
    private var window: ClosedRange<Int>? {
        guard position >= 1, position <= 5 else { return nil }
        let base = rootFretLow + scale.intervals.sorted()[position - 1]
        return base...(base + 4)
    }

    private func positions(root wantRoot: Bool) -> [FretPosition] {
        let set = scaleSet
        let win = window
        let lower = max(0, win?.lowerBound ?? 0)
        let upper = min(genMax, win?.upperBound ?? allLagenMax)
        guard lower <= upper else { return [] }
        var res: [FretPosition] = []
        for s in BassString.allCases {
            for f in lower...upper {
                let notePC = pc(s.notePattern[f % 12])
                guard set.contains(notePC) else { continue }
                let isRoot = notePC == rootPC
                if wantRoot == isRoot { res.append(FretPosition(string: s, fret: f)) }
            }
        }
        return res
    }

    var scaleMarkers: [FretPosition] { positions(root: false) }
    var rootMarkers: [FretPosition] { positions(root: true) }

    /// Hinweis auf die relative Dur/Moll-Verwandtschaft (gleiche Töne).
    var relativeHint: String {
        let idx = rootPC
        if scale == .minor {
            let rel = NoteName.allNotes[(idx + 3) % 12]
            return "\(root.rawValue)-Moll-Pentatonik = \(rel.rawValue)-Dur-Pentatonik (gleiche Töne)"
        } else {
            let rel = NoteName.allNotes[(idx + 9) % 12]
            return "\(root.rawValue)-Dur-Pentatonik = \(rel.rawValue)-Moll-Pentatonik (gleiche Töne)"
        }
    }
}

#Preview {
    PentatonicView()
}
