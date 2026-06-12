import SwiftUI

struct NoteButtonsView: View {
    let notes: [NoteName]
    let isDisabled: Bool
    let onNoteTapped: (NoteName) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Welche Note ist markiert?")
                .font(.headline)

            // Arrange buttons in a flowing grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: min(notes.count, 7)), spacing: 12) {
                ForEach(notes) { note in
                    Button(action: { onNoteTapped(note) }) {
                        Text(note.rawValue)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .frame(minWidth: 60, minHeight: 60)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
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
            }

            Text("Tastatur: C, D, E, F, G, A, B")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

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
