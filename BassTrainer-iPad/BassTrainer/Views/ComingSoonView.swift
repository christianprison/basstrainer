import SwiftUI

/// Platzhalter für noch nicht implementierte Übungen ("Kommt bald").
struct ComingSoonView: View {
    let title: String
    let subtitle: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { dismiss() } label: {
                    Label("Menü", systemImage: "chevron.left")
                }
                Spacer()
            }

            Spacer()
            Image(systemName: "hammer.fill")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text("Diese Übung kommt bald.")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ComingSoonView(title: "Quinten", subtitle: "Quintenzirkel auf dem Griffbrett")
}
