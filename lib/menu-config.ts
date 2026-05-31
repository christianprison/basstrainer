// Menüstruktur für das Hauptmenü.
// Ein "mode" verweist auf eine echte Trainings-Ansicht; ohne "mode" ist es
// eine Kategorie mit Untereinträgen. "implemented: false" rendert einen
// "Kommt bald"-Platzhalter.

export type MenuMode = "fretboard" | "placeholder"

export interface MenuItem {
  id: string
  label: string
  description?: string
  children?: MenuItem[]
  mode?: MenuMode
}

export const MAIN_MENU: MenuItem[] = [
  {
    id: "griffbrett",
    label: "Griffbrett",
    description: "Notenerkennung & Navigation auf dem Griffbrett",
    children: [
      { id: "quinten", label: "Quinten", description: "Quintenzirkel auf dem Griffbrett", mode: "placeholder" },
      { id: "quarten", label: "Quarten", description: "Quartensprünge üben", mode: "placeholder" },
      {
        id: "griffbrett-trainer",
        label: "Griffbrett",
        description: "Das klassische BassTrainer-Training",
        mode: "fretboard",
      },
    ],
  },
  {
    id: "praezision",
    label: "Präzision",
    description: "Anschlag & Timing",
    children: [
      { id: "pick", label: "Pick", description: "Präzision mit Plektrum", mode: "placeholder" },
      { id: "fingered", label: "Fingered", description: "Präzision mit Fingern", mode: "placeholder" },
    ],
  },
  {
    id: "improvisation",
    label: "Improvisation",
    description: "Skalen & freies Spiel",
    children: [
      {
        id: "pentatonic-shapes",
        label: "Pentatonic Shapes",
        description: "Pentatonik-Patterns über das Griffbrett",
        mode: "placeholder",
      },
    ],
  },
  {
    id: "songs",
    label: "Songs",
    description: "Komplette Songs üben",
    children: [
      { id: "kitn", label: "Killing in the Name of", description: "Rage Against the Machine", mode: "placeholder" },
      { id: "word-up", label: "Word up", description: "Cameo", mode: "placeholder" },
    ],
  },
]
