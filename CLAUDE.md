# CLAUDE.md

Leitfaden für Claude Code / KI-Agents, die in diesem Repository arbeiten.

## Projektüberblick

**BassTrainer** ist eine interaktive Musik-Trainingsanwendung zum Üben der Bass-Griffbrett-
Navigation und Notenerkennung. Sie bietet 8 progressive Schwierigkeitslevel, Audio-Feedback über
die Web Audio API und eine visuelle Griffbrett-Darstellung.

Das Repo enthält **zwei getrennte Implementierungen**:

- **Web-App** (Hauptprojekt): Next.js, deployed auf Vercel.
- **iPad-App** (`BassTrainer-iPad/`): eigenständige native SwiftUI-App (iOS 17+). Unabhängig von der
  Web-App — Änderungen an der einen wirken sich nicht auf die andere aus.

> Hinweis: Die Web-App wird über [v0.app](https://v0.app) gepflegt und automatisch in dieses Repo
> gesynct (siehe `README.md`). Manuelle Änderungen hier können bei einem v0-Sync überschrieben werden.

## Tech-Stack (Web)

- **Framework:** Next.js 14 (App Router) mit React 19 und TypeScript
- **Styling:** Tailwind CSS 4 (+ PostCSS), shadcn/ui-Komponenten auf Radix UI
- **Formulare/Validierung:** React Hook Form + Zod
- **Audio:** Web Audio API (eigene `SimpleBeepGenerator`-Klasse)
- **Sonstiges:** Recharts (Diagramme), Lucide (Icons), next-themes, canvas-confetti, Vercel Analytics
- **Paketmanager:** **pnpm** (`pnpm-lock.yaml` ist die maßgebliche Lockfile)

## Befehle

```bash
pnpm install      # Abhängigkeiten installieren
pnpm dev          # Dev-Server starten (http://localhost:3000)
pnpm build        # Production-Build
pnpm start        # Production-Server starten
pnpm lint         # ESLint (next lint)
```

(npm/yarn funktionieren ebenfalls, aber pnpm passt zur vorhandenen Lockfile.)

## Verzeichnisstruktur (Web)

```
app/
  layout.tsx               # Root-Layout + Metadata
  page.tsx                 # Einstiegspunkt → rendert <BassTrainer />
  globals.css              # globale Tailwind-/CSS-Styles
components/
  bass-trainer.tsx         # Hauptkomponente: Spiel-Logik, Audio-Engine, UI-State
  theme-provider.tsx       # next-themes Wrapper
  ui/                      # shadcn/ui-Komponenten (button, card, progress, toast, ...)
hooks/
  use-toast.ts             # Toast-Hook
lib/
  calibrated-positions.ts       # Griffbrett-Koordinaten (Konstante) — NICHT einfach ändern
  calibrated-positions.test.ts  # Validierung, läuft beim Import
  utils.ts                      # cn() (clsx + tailwind-merge)
scripts/
  validate-calibrated-positions.ts  # Validierungs-Skript für die Positionen
public/                    # statische Assets
BassTrainer-iPad/          # separate native SwiftUI-App (eigenes Xcode-Projekt)
```

## Architektur / Einstiegspunkte

- Einstieg: `app/page.tsx` rendert `<BassTrainer />` aus `components/bass-trainer.tsx`.
- `components/bass-trainer.tsx` ist die große, zentrale Komponente: enthält Spiel-/Level-Logik,
  UI-State und die Audio-Engine `SimpleBeepGenerator` (`playBeep`, `playFanfare`, `playFireworks`, ...).
- Griffbrett-Positionen kommen aus der unveränderlichen Konstante in `lib/calibrated-positions.ts`
  (5 Saiten × Bünde mit kalibrierten Pixel-Koordinaten).

## Tests / Validierung

Es gibt **kein** Jest/Vitest. Die Korrektheit der Griffbrett-Daten wird über eine Inline-Validierung
sichergestellt: `lib/calibrated-positions.test.ts` bzw. `scripts/validate-calibrated-positions.ts`
prüfen die Positionen (läuft beim Import/Start). Wenn du `calibrated-positions.ts` anfasst, stelle
sicher, dass diese Validierung weiterhin durchläuft.

## Konventionen

- UI über shadcn/ui-Komponenten aus `components/ui/`; bedingtes Styling mit `cn()` aus `lib/utils.ts`.
- Tailwind-Utility-Klassen statt eigener CSS-Dateien (Ausnahme: `app/globals.css`).
- Import-Alias `@/` (siehe `components.json` / `tsconfig.json`).
- Toasts über den `useToast()`-Hook.

## Wichtige Fallstricke

- **`lib/calibrated-positions.ts` ist „heilig"**: Die Werte sind kalibrierte Griffbrett-Koordinaten.
  Nicht ohne Re-Kalibrierung ändern — sonst stimmen die Notenpositionen im UI nicht mehr.
- **Build-Fehler werden ignoriert:** `next.config.mjs` setzt `eslint.ignoreDuringBuilds` und
  `typescript.ignoreBuildErrors` auf `true`. Ein grüner Build bedeutet **nicht**, dass keine
  TS-/Lint-Fehler vorliegen — `pnpm lint` und `tsc` ggf. separat prüfen.
- **v0.app-Sync:** Die Web-App wird von v0.app gesynct; rein lokale Änderungen können dadurch
  überschrieben werden.
- **iPad-App ist getrennt:** `BassTrainer-iPad/` ist eine eigenständige SwiftUI-App — kein
  gemeinsamer Code mit der Web-App.
