import SwiftUI

struct NoteButtonsView: View {
    let notes: [NoteName]
    let isDisabled: Bool
    let onNoteTapped: (NoteName) -> Void

    private let buttonSize: CGFloat = 56
    // Höhe um 80 reduziert (war 300) und shiftY im gleichen Maß (war 90 → 10):
    // der Drehpunkt bleibt dadurch identisch, die Buttons stehen unverändert,
    // nur der ungenutzte Leerraum unten entfällt → kein Scrollbalken mehr.
    private let containerHeight: CGFloat = 220
    // Ellipse statt Kreis: breiter als hoch → untere Töne liegen weiter innen.
    private let outerRX: CGFloat = 185       // Naturtöne, horizontal
    private let outerRY: CGFloat = 140       // Naturtöne, vertikal
    private let innerRX: CGFloat = 104       // Halbtöne, horizontal
    private let innerRY: CGFloat = 74        // Halbtöne, vertikal
    private let shiftX: CGFloat = 74         // weiter zur Mitte
    private let shiftY: CGFloat = 10         // mit containerHeight reduziert (Drehpunkt bleibt gleich)

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
        // Drehpunkt weiter innen und oben (statt direkt in der Ecke).
        let margin = buttonSize / 2 + 6
        let leftPivot = CGPoint(x: margin + shiftX, y: size.height - margin - shiftY)
        let rightPivot = CGPoint(x: size.width - margin - shiftX, y: size.height - margin - shiftY)

        let sorted = notes.sorted { pitchClass($0) < pitchClass($1) }
        let leftNat = sorted.filter { pitchClass($0) <= 5 && isNatural($0) }
        let leftSharp = sorted.filter { pitchClass($0) <= 5 && !isNatural($0) }
        let rightNat = sorted.filter { pitchClass($0) >= 6 && isNatural($0) }
        let rightSharp = sorted.filter { pitchClass($0) >= 6 && !isNatural($0) }

        // Links C…F (links nach rechts: C oben → F weit innen).
        place(leftNat, pivot: leftPivot, rx: outerRX, ry: outerRY, fromDeg: 90, toDeg: 18, into: &result)
        place(leftSharp, pivot: leftPivot, rx: innerRX, ry: innerRY, fromDeg: 90, toDeg: 18, into: &result)
        // Rechts G…B (links nach rechts: G innen → B außen).
        place(rightNat, pivot: rightPivot, rx: outerRX, ry: outerRY, fromDeg: 162, toDeg: 90, into: &result)
        place(rightSharp, pivot: rightPivot, rx: innerRX, ry: innerRY, fromDeg: 162, toDeg: 90, into: &result)
        return result
    }

    private func place(_ group: [NoteName], pivot: CGPoint, rx: CGFloat, ry: CGFloat,
                       fromDeg: Double, toDeg: Double, into result: inout [NoteName: CGPoint]) {
        let n = group.count
        let rxd = Double(rx)
        let ryd = Double(ry)
        let px = Double(pivot.x)
        let py = Double(pivot.y)
        for (i, note) in group.enumerated() {
            let frac = n <= 1 ? 0.5 : Double(i) / Double(n - 1)
            let deg = fromDeg + (toDeg - fromDeg) * frac
            let rad = deg * Double.pi / 180
            result[note] = CGPoint(x: px + cos(rad) * rxd, y: py - sin(rad) * ryd)
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
