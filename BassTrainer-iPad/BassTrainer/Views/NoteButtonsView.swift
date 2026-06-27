import SwiftUI

struct NoteButtonsView: View {
    let notes: [NoteName]
    let isDisabled: Bool
    let onNoteTapped: (NoteName) -> Void

    private let buttonSize: CGFloat = 62
    private let containerHeight: CGFloat = 260
    private let outerRadius: CGFloat = 140   // Naturtöne
    private let innerRadius: CGFloat = 84    // Halbtöne (weiter innen)

    var body: some View {
        VStack(spacing: 8) {
            Text("Welche Note ist markiert?")
                .font(.headline)

            // Daumenfreundlich: linke Hälfte (C…F) im Bogen um die linke untere
            // Ecke, rechte Hälfte (G…B) um die rechte untere Ecke.
            GeometryReader { geo in
                let positions = layout(in: geo.size)
                ZStack {
                    ForEach(notes) { note in
                        noteButton(note)
                            .position(positions[note] ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                    }
                }
            }
            .frame(height: containerHeight)

            Text("Tastatur: C, D, E, F, G, A, B")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func noteButton(_ note: NoteName) -> some View {
        Button(action: { onNoteTapped(note) }) {
            Text(note.rawValue)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .keyboardShortcut(keyboardShortcut(for: note), modifiers: [])
    }

    /// Bogen-Positionen: Töne mit Tonklasse 0–5 (C…F) links, 6–11 (Fis…B)
    /// rechts. Naturtöne außen, Halbtöne auf kleinerem Radius weiter innen.
    private func layout(in size: CGSize) -> [NoteName: CGPoint] {
        var result: [NoteName: CGPoint] = [:]
        let margin = buttonSize / 2 + 8
        let leftPivot = CGPoint(x: margin, y: size.height - margin)
        let rightPivot = CGPoint(x: size.width - margin, y: size.height - margin)

        let sorted = notes.sorted { pitchClass($0) < pitchClass($1) }
        let leftNat = sorted.filter { pitchClass($0) <= 5 && isNatural($0) }
        let leftSharp = sorted.filter { pitchClass($0) <= 5 && !isNatural($0) }
        let rightNat = sorted.filter { pitchClass($0) >= 6 && isNatural($0) }
        let rightSharp = sorted.filter { pitchClass($0) >= 6 && !isNatural($0) }

        place(leftNat, pivot: leftPivot, radius: outerRadius, fromDeg: 95, toDeg: 8, into: &result)
        place(leftSharp, pivot: leftPivot, radius: innerRadius, fromDeg: 95, toDeg: 8, into: &result)
        place(rightNat, pivot: rightPivot, radius: outerRadius, fromDeg: 85, toDeg: 172, into: &result)
        place(rightSharp, pivot: rightPivot, radius: innerRadius, fromDeg: 85, toDeg: 172, into: &result)
        return result
    }

    private func place(_ group: [NoteName], pivot: CGPoint, radius: CGFloat,
                       fromDeg: Double, toDeg: Double, into result: inout [NoteName: CGPoint]) {
        let n = group.count
        let r = Double(radius)
        let px = Double(pivot.x)
        let py = Double(pivot.y)
        for (i, note) in group.enumerated() {
            let frac = n <= 1 ? 0.5 : Double(i) / Double(n - 1)
            let deg = fromDeg + (toDeg - fromDeg) * frac
            let rad = deg * Double.pi / 180
            result[note] = CGPoint(x: px + cos(rad) * r, y: py - sin(rad) * r)
        }
    }

    private func pitchClass(_ n: NoteName) -> Int { NoteName.allCases.firstIndex(of: n) ?? 0 }
    private func isNatural(_ n: NoteName) -> Bool { NoteName.naturalNotes.contains(n) }

    private func keyboardShortcut(for note: NoteName) -> KeyEquivalent {
        switch note {
        case .c: return "c"
        case .d: return "d"
        case .e: return "e"
        case .f: return "f"
        case .g: return "g"
        case .a: return "a"
        case .b: return "b"
        default: return KeyEquivalent(Character("\0"))
        }
    }
}

#Preview {
    NoteButtonsView(
        notes: NoteName.naturalNotes,
        isDisabled: false,
        onNoteTapped: { _ in }
    )
}
