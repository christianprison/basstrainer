import SwiftUI

/// Ein Hilfe-Thema (aufklappbar).
struct HelpTopic: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let body: String
}

/// Kleine In-App-Hilfe mit Troubleshooting-/Bedien-Hinweisen (Werkzeuge → Hilfe).
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let topics: [HelpTopic] = [
        HelpTopic(
            title: "TestFlight-Upload schlägt fehl: Vereinbarung",
            systemImage: "doc.badge.gearshape",
            body: """
            Meldung: „A required agreement is missing or has expired."

            Das ist KEIN Build-/Code-Problem — die App wurde fertig gebaut. Nur der \
            Upload zu TestFlight ist blockiert, weil Apple eine Vereinbarung verlangt, \
            die (neu) akzeptiert werden muss (z. B. das Apple Developer Program License \
            Agreement oder „Paid Apps / Agreements, Tax, and Banking"). Solche Agreements \
            laufen periodisch ab oder werden von Apple aktualisiert.

            Lösung (nur der Account Holder kann das):
            1. appstoreconnect.apple.com als Account Holder einloggen.
            2. Business → „Agreements, Tax, and Banking" öffnen (bzw. oben das gelbe \
            Banner „Review Agreement").
            3. Die ausstehende/abgelaufene Vereinbarung akzeptieren (ggf. auch unter \
            developer.apple.com → „Review Agreement").

            Danach den Build-Workflow neu auslösen (GitHub → Actions → „Re-run") — am Code \
            muss nichts geändert werden.
            """
        ),
        HelpTopic(
            title: "Audio: USB-Interface (Ein-/Ausgang)",
            systemImage: "pianokeys",
            body: """
            Bei einem USB-Audio-Interface (z. B. UM2) koppelt iOS Eingang und Ausgang \
            hart zusammen. „Bass übers Interface rein UND Metronom über den \
            iPad-Lautsprecher raus" lässt iOS in einer normalen Aufnahme-Session NICHT \
            zu — der eine Override zieht den anderen mit.

            Praktisch heißt das: Schließe Kopfhörer/Monitore an den Ausgang des \
            Interfaces an, dann hörst du Metronom/Wiedergabe dort. Der Bass-Eingang \
            wird automatisch aufs USB-Interface gelegt (Noten-Erkennung, Oktaven, \
            Intro einspielen).
            """
        ),
        HelpTopic(
            title: "Kurator-Modus freischalten",
            systemImage: "key",
            body: """
            Song-Anfänge in die zentrale DB schreiben darf nur ein Kurator.

            1. Werkzeuge → Einstellungen öffnen und die angezeigte Geräte-ID (uid) \
            kopieren.
            2. Der Owner trägt diese uid einmal in die Tabelle „curators" ein.
            3. Danach funktioniert „In Datenbank speichern" beim Intro einspielen.

            Vorher kommt beim Speichern bewusst „Nicht freigeschaltet" (HTTP 403). \
            Lesen (z. B. die Übung „Songanfänge merken") geht immer.
            """
        ),
        HelpTopic(
            title: "Intro einspielen: Erkennung justieren",
            systemImage: "waveform",
            body: """
            Unter dem Tab läuft eine Live-Hüllkurve: blaue Fläche = Pegel, orange \
            gestrichelt = Auslöseschwelle, grüne Linie = erkannter Anschlag.

            • Töne werden nicht erkannt (Pegel bleibt unter der Schwelle): \
            Empfindlichkeit ↑, Gate ↓, ggf. Gain ↑.
            • Ein Anschlag wird doppelt erkannt: Refraktär ↑.
            • Marker im Sustain/Brummen: Gate ↑.
            • Schnelle Läufe verschluckt: Refraktär ↓, Attack ↑.

            „Standardwerte" setzt alle Regler zurück. Erkannte Töne werden auf 16tel \
            quantisiert; die Notendauer wird aus dem Abstand zum nächsten Anschlag \
            abgeleitet.
            """
        ),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(topics) { topic in
                    DisclosureGroup {
                        Text(topic.body)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(.vertical, 6)
                    } label: {
                        Label(topic.title, systemImage: topic.systemImage)
                    }
                }
            }
            .navigationTitle("Hilfe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Menü", systemImage: "chevron.left") }
                }
            }
        }
    }
}
