import SwiftUI

/// Zeigt die pro Song hinterlegten Tipps: Text-Hinweise und saitige Bass-Tabs.
/// Tabs werden in Monospace dargestellt (eine Zeile je Saite) und scrollen
/// horizontal, falls sie breiter als der Bildschirm sind.
struct TipsView: View {
    let tips: [SongTip]

    var body: some View {
        if tips.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "lightbulb").font(.system(size: 34)).foregroundColor(.secondary)
                Text("Keine Tipps hinterlegt").font(.headline)
                Text("Song-Tipps werden zentral gepflegt und erscheinen hier.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(tips) { tip in tipCard(tip) }
                }
                .padding(20)
            }
        }
    }

    private func tipCard(_ tip: SongTip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = tip.title, !title.isEmpty {
                Label(title, systemImage: "lightbulb.fill")
                    .font(.headline).foregroundColor(.accentColor)
            }
            if let text = tip.text, !text.isEmpty {
                Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            if let tab = tip.tab, !tab.isEmpty {
                tabView(tab)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private func tabView(_ lines: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(lines.joined(separator: "\n"))
                .font(.system(.callout, design: .monospaced))
                .fixedSize()
                .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 1))
    }
}

#Preview {
    TipsView(tips: [
        SongTip(title: "Wordup", text: "Hand über Hals, nicht über Pickup. Tiefe Lage (E-Saite). Saite „dahinter\" anpeilen.", tab: nil),
        SongTip(title: "Killing In The Name Of", text: "Kleiner Finger für die 5.", tab: [
            "G|-----------------|",
            "D|-------3h4-5--3---|",
            "A|--3-5-------3-----|",
            "E|--3--------------0-1-0-|",
        ]),
    ])
}
