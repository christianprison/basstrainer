import SwiftUI
import UIKit

/// Zeigt die eigene anonyme uid an. Der Owner trägt sie einmal in `curators`
/// ein, damit Schreibzugriffe (Song-Anfänge) erlaubt sind.
struct CuratorSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var uid: String?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Um Song-Anfänge in die zentrale Datenbank zu schreiben, muss deine Geräte-ID (uid) in der Tabelle „curators“ stehen. Bis dahin sind Schreibzugriffe gesperrt (Lesen geht immer).")
                        .font(.footnote).foregroundColor(.secondary)
                } header: {
                    Text("Kurator-Modus")
                }

                Section("Deine uid") {
                    if loading {
                        ProgressView()
                    } else if let uid {
                        Text(uid)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = uid
                        } label: {
                            Label("uid kopieren", systemImage: "doc.on.doc")
                        }
                    } else {
                        Text(error ?? "Unbekannter Fehler").foregroundColor(.red).font(.caption)
                        Button("Erneut versuchen") { Task { await load() } }
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Menü", systemImage: "chevron.left") }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            uid = try await SupabaseAuth.shared.userID()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
