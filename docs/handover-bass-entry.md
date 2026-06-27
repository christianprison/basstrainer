# Übergabe an die lighting.ai-Session — Anker „Basseinsatz" für Audio-Vorlauf

## Ziel
In der Übung **„Songanfänge merken"** soll BassTrainer – wenn der Bass **nicht**
im ersten Takt einsetzt – statt eines Metronom-Einzählers die **letzten 2 Takte
vor dem Basseinsatz aus dem `playalong`-Track** abspielen (musikalischer
Anlauf). Dafür muss pro Song bekannt sein, **wo** der Bass einsetzt.

## Was fehlt: ein Anker pro Song
Bitte den Basseinsatz hinterlegen und read-only exponieren. **Empfehlung:**

- Spalte **`entry_bar`** (int, nullable) — die **Taktnummer**, in der der erste
  Bass-Ton klingt (1-basiert, passend zu `song_timeline_public.bar_num`).
- Exponiert in **`song_intro_public`** (gleicher Wert für alle Zeilen eines
  Songs; die App liest ihn aus der ersten Zeile).

`entry_bar = 1` oder `null` ⇒ Bass beginnt am Anfang ⇒ App nutzt den normalen
2-Takt-Metronom-Einzähler.

### Alternative (falls einfacher)
- Spalte **`entry_sec`** (numeric) — **absolute Zeit** des Basseinsatzes im
  `playalong` (Sekunden). Dann braucht die App keine Timeline; Vorlauf =
  `entry_sec − 2·(60/bpm·4)` … `entry_sec`. Weniger genau bei Tempowechseln.

(Bitte EINE der beiden Varianten. `entry_bar` ist genauer, weil die App die
exakten Zeiten aus `song_timeline_public.t_start` nimmt.)

## Was BassTrainer damit tut
- Liest `entry_bar` aus `song_intro_public`.
- Wenn `entry_bar > 1` **und** Song hat `playalong` **und** Timeline-`t_start`
  für `entry_bar-2` und `entry_bar`:
  → spielt `playalong` von `t_start(entry_bar-2)` bis `t_start(entry_bar)`,
  dann „Jetzt spielen!" ab dem Basseinsatz. Erwartete Tonzeiten (`beat`) zählen
  ab diesem Einsatz (beat 0 = Basseinsatz).
- Sonst (kein Anker / kein Playalong / keine Timeline) → **Metronom-Einzähler**
  (Fallback, wie bisher).
- Alles read-only.

## Hinweise
- Nur Songs mit Timeline (`song_timeline_public`) **und** `playalong` bekommen
  den Audio-Vorlauf; der Rest bleibt beim Metronom — sauberer Fallback.
- `entry_bar` ist additiv: solange die Spalte fehlt/`null` ist, ändert sich
  nichts (App fällt auf Metronom zurück). Ich kann die App also schon
  vorbereiten und es aktiviert sich, sobald Werte da sind.
