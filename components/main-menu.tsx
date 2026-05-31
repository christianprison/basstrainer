"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { ArrowLeft, ChevronRight } from "lucide-react"
import { MAIN_MENU, type MenuItem } from "@/lib/menu-config"
import BassTrainer from "@/components/bass-trainer"
import ComingSoon from "@/components/coming-soon"

// Navigations-Shell: rendert das Hauptmenü, Untermenüs, den echten
// Griffbrett-Trainer oder einen "Kommt bald"-Platzhalter.
export default function MainMenu() {
  // Pfad der angeklickten Kategorien (z.B. ["griffbrett"]).
  const [path, setPath] = useState<string[]>([])
  // Aktiver Trainings-Modus (Blatt-Eintrag), falls einer gewählt wurde.
  const [active, setActive] = useState<MenuItem | null>(null)

  // Aktuelle Ebene anhand des Pfads bestimmen.
  let level: MenuItem[] = MAIN_MENU
  const trail: MenuItem[] = []
  for (const id of path) {
    const found = level.find((item) => item.id === id)
    if (!found || !found.children) break
    trail.push(found)
    level = found.children
  }

  // Aktiver Modus: echte App oder Platzhalter.
  if (active) {
    if (active.mode === "fretboard") {
      return (
        <div className="relative">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setActive(null)}
            className="fixed left-4 top-4 z-50"
          >
            <ArrowLeft className="mr-2 h-4 w-4" />
            Menü
          </Button>
          <BassTrainer />
        </div>
      )
    }
    return <ComingSoon title={active.label} description={active.description} onBack={() => setActive(null)} />
  }

  const currentTitle = trail.length > 0 ? trail[trail.length - 1].label : "BassTrainer"
  const currentDescription = trail.length > 0 ? trail[trail.length - 1].description : "Wähle einen Trainingsbereich"

  const handleSelect = (item: MenuItem) => {
    if (item.children && item.children.length > 0) {
      setPath([...path, item.id])
    } else {
      setActive(item)
    }
  }

  const handleBack = () => setPath(path.slice(0, -1))

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-6 p-6">
      <div className="w-full max-w-md">
        <div className="mb-6 flex items-center gap-3">
          {path.length > 0 && (
            <Button variant="ghost" size="icon" onClick={handleBack} aria-label="Zurück">
              <ArrowLeft className="h-5 w-5" />
            </Button>
          )}
          <div>
            <h1 className="text-2xl font-bold">{currentTitle}</h1>
            {currentDescription && <p className="text-sm text-muted-foreground">{currentDescription}</p>}
          </div>
        </div>

        <div className="flex flex-col gap-3">
          {level.map((item) => (
            <Card
              key={item.id}
              className="cursor-pointer transition-colors hover:bg-accent"
              onClick={() => handleSelect(item)}
            >
              <CardContent className="flex items-center justify-between py-4">
                <div>
                  <div className="font-semibold">{item.label}</div>
                  {item.description && <div className="text-sm text-muted-foreground">{item.description}</div>}
                </div>
                <ChevronRight className="h-5 w-5 shrink-0 text-muted-foreground" />
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    </div>
  )
}
