import SwiftUI

/// Zeigt die pro Song hinterlegten Tipps: zentrale (read-only) und persönliche
/// (in der App editierbare). Text-Hinweise und saitige Bass-Tabs; Tabs in
/// Monospace (eine Zeile je Saite), horizontal scrollbar.
struct TipsView: View {
    let centralTips: [SongTip]
    @ObservedObject var store: SongTipStore
    let songID: String

    @State private var editing: PersonalTip?
    @State private var showEditor = false
    @State private var toDelete: PersonalTip?

    private var personal: [PersonalTip] { store.tips(forSong: songID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if centralTips.isEmpty && personal.isEmpty {
                    emptyHint
                }
                if !centralTips.isEmpty {
                    sectionHeader("Tipps")
                    ForEach(centralTips) { tip in TipCard(tip: tip) }
                }

                sectionHeader("Meine Notizen")
                ForEach(personal) { tip in
                    TipCard(tip: tip.asSongTip) {
                        Menu {
                            Button { editing = tip; showEditor = true } label: { Label("Bearbeiten", systemImage: "pencil") }
                            Button(role: .destructive) { toDelete = tip } label: { Label("Löschen", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.title3)
                        }
                    }
                }
                Button {
                    editing = PersonalTip(songID: songID)
                    showEditor = true
                } label: {
                    Label("Tipp hinzufügen", systemImage: "plus.circle.fill").font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .sheet(isPresented: $showEditor) {
            if let draft = editing {
                TipEditorView(draft: draft) { saved in
                    Task {
                        if personal.contains(where: { $0.id == saved.id }) {
                            await store.update(saved)
                        } else {
                            await store.add(songID: songID, title: saved.title, text: saved.text, tab: saved.tab)
                        }
                    }
                }
            }
        }
        .confirmationDialog("Notiz löschen?",
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible, presenting: toDelete) { tip in
            Button("Löschen", role: .destructive) { Task { await store.remove(tip) }; toDelete = nil }
            Button("Abbrechen", role: .cancel) { toDelete = nil }
        } message: { _ in Text("Diese persönliche Notiz wird gelöscht.") }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "lightbulb").font(.system(size: 34)).foregroundColor(.secondary)
            Text("Noch keine Tipps").font(.headline)
            Text("Zentrale Tipps erscheinen hier automatisch. Eigene Notizen kannst du unten hinzufügen.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
    }
}

/// Eine Tipp-Karte (Text + optionaler Bass-Tab) mit optionalem Zusatz-Button.
private struct TipCard<Trailing: View>: View {
    let tip: SongTip
    @ViewBuilder var trailing: () -> Trailing

    init(tip: SongTip, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.tip = tip
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                if let title = tip.title, !title.isEmpty {
                    Label(title, systemImage: "lightbulb.fill").font(.headline).foregroundColor(.accentColor)
                }
                Spacer()
                trailing()
            }
            if let text = tip.text, !text.isEmpty {
                Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            if let tab = tip.tab, !tab.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(tab.joined(separator: "\n"))
                        .font(.system(.callout, design: .monospaced)).fixedSize().padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

/// Editor für eine persönliche Notiz (Titel, Text, saitiger Bass-Tab).
private struct TipEditorView: View {
    @State var draft: PersonalTip
    let onSave: (PersonalTip) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var text: String = ""
    @State private var tabText: String = ""

    private let template = "G|--------------------|\nD|--------------------|\nA|--------------------|\nE|--------------------|"

    var body: some View {
        NavigationStack {
            Form {
                Section("Titel") {
                    TextField("z. B. Killing In The Name Of", text: $title)
                }
                Section("Hinweis") {
                    TextEditor(text: $text).frame(minHeight: 80)
                }
                Section {
                    TextEditor(text: $tabText)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Leere Tab-Vorlage einfügen") { if tabText.isEmpty { tabText = template } }
                        .font(.caption)
                } header: {
                    Text("Bass-Tab (eine Zeile je Saite)")
                } footer: {
                    Text("Monospace-Tab, z. B. \"A|-3-5---\". Leer lassen, wenn nicht benötigt.")
                }
            }
            .navigationTitle("Notiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") { save() }.disabled(!canSave)
                }
            }
            .onAppear {
                title = draft.title ?? ""
                text = draft.text ?? ""
                tabText = (draft.tab ?? []).joined(separator: "\n")
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            || !text.trimmingCharacters(in: .whitespaces).isEmpty
            || !tabText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        var t = draft
        t.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : title
        t.text = text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : text
        let lines = tabText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let trimmed = tabText.trimmingCharacters(in: .whitespacesAndNewlines)
        t.tab = trimmed.isEmpty ? nil : lines
        onSave(t)
        dismiss()
    }
}
