import SwiftUI

/// Navigations-Shell: Hauptmenü mit Kategorien/Untermenüs, startet die
/// jeweilige Übung als Vollbild. Spiegelt die Web-Version.
struct MainMenuView: View {
    var body: some View {
        NavigationStack {
            MenuLevelView(
                title: "BassTrainer",
                subtitle: "Wähle einen Trainingsbereich",
                items: MenuConfig.main
            )
            // Einmalige Registrierung für alle Kategorie-Pushes im Stack.
            .navigationDestination(for: MenuItem.self) { item in
                MenuLevelView(title: item.label, subtitle: item.description, items: item.children ?? [])
            }
        }
    }
}

/// Eine Menüebene: Kategorien pushen tiefer, Blätter starten ihre Übung.
private struct MenuLevelView: View {
    let title: String
    let subtitle: String?
    let items: [MenuItem]

    @State private var activeLeaf: MenuItem?

    var body: some View {
        List {
            if let subtitle {
                Section {
                    rows
                } header: {
                    Text(subtitle).textCase(nil)
                }
            } else {
                rows
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $activeLeaf) { leaf in
            destination(for: leaf)
                .logPractice(leaf.label, active: leaf.mode?.isPractice == true, detail: leaf.description)
        }
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(items) { item in
            if let children = item.children, !children.isEmpty {
                NavigationLink(value: item) {
                    MenuRow(item: item)
                }
            } else {
                Button { activeLeaf = item } label: {
                    MenuRow(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func destination(for item: MenuItem) -> some View {
        switch item.mode {
        case .fretboard:
            ContentView()
        case .warmup:
            WarmupView()
        case .orientation:
            OrientationView()
        case .pickOctaves:
            PickOctavesView()
        case .pentatonic:
            PentatonicView()
        case .practiceLog:
            PracticeLogView()
        case .todayPlan:
            TodayView()
        case .tuner:
            NoteRecognizerView()
        case .precisionOctaves:
            PrecisionOctavesView()
        case .songsList:
            SongsView(source: .setlist)
        case .repertoireList:
            SongsView(source: .repertoire)
        case .introQuiz:
            IntroQuizView()
        case .introRecorder:
            IntroRecorderView()
        case .latencyCalibration:
            LatencyCalibrationView()
        case .curatorSettings:
            CuratorSettingsView()
        case .help:
            HelpView()
        case .practiceClass:
            PracticeClassView(reason: item.practiceReason ?? .other)
        default:
            ComingSoonView(title: item.label, subtitle: item.description)
        }
    }
}

private struct MenuRow: View {
    let item: MenuItem
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.label).font(.headline)
            if let d = item.description {
                Text(d).font(.subheadline).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

#Preview {
    MainMenuView().preferredColorScheme(.dark)
}
