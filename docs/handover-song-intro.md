# Übergabe an die lighting.ai-Session — Song-Anfänge für die Übung „Anfänge lernen"

## TL;DR
BassTrainer bekommt eine neue Übung **„Anfänge lernen"**: Die App nennt einen
Songtitel, gibt das Tempo per Metronom vor, der Spieler spielt die **ersten
Töne**, und das Mikrofon prüft **Tonhöhe + Rhythmus**. Dafür muss die App pro
Song die **Soll-Anfänge** kennen (Tonhöhen + Timing). Diese Daten gibt es bisher
nicht — bitte als **read-only View** bereitstellen. BassTrainer bleibt reiner
Konsument; `service_role` nie im Client.

## Bitte bereitstellen: View `song_intro_public`

```
GET /rest/v1/song_intro_public?song_id=eq.<ID>&order=idx
```

| Spalte | Typ | Bedeutung |
|---|---|---|
| `song_id` | text (FK → songs.id) | welcher Song |
| `idx` | int | Reihenfolge des Tons, 1..N (lückenlos) |
| `midi` | int | **klingende** Tonhöhe als MIDI-Nummer (siehe unten) |
| `beat` | numeric | Anschlagposition in Viertel-Schlägen ab Takt-1-Downbeat (1 = 0.0). Auftakt/Pickup als negativer Wert möglich. |
| `duration_beats` | numeric, optional | Notenlänge in Schlägen (für Anzeige; Bewertung nutzt v. a. den Anschlag) |
| `string` | int, optional | Saite (Anzeige-Hinweis; E=1 … G=4) |
| `fret` | int, optional | Bund (Anzeige-Hinweis) |

Tempo kommt aus `songs.bpm` (bereits vorhanden) — **nicht** zusätzlich nötig.

### Wichtig: MIDI = klingende Tonhöhe
Bass wird üblicherweise **eine Oktave höher notiert, als er klingt**. Das
Mikrofon hört die **klingende** Tonhöhe — also bitte die klingende MIDI-Nummer
eintragen. Referenz (leere Saiten, klingend):
`E1 = 28`, `A1 = 33`, `D2 = 38`, `G2 = 43`.

### Wie viel ist „der Anfang"? (Empfehlung)
Die **ersten 1–2 Takte** bzw. die erste wiedererkennbare Phrase — typischerweise
**4–8 Töne**. Die genaue Anzahl bestimmt ihr pro Song über `idx`; die App spielt
einfach alle gelieferten Töne ab `idx = 1`.

### Beispiel (illustrativ)
```
song_id  idx  midi  beat  duration_beats  string  fret
5iZfKj    1    38    0.0   0.5             3       0     # D2 auf 1
5iZfKj    2    38    0.5   0.5             3       0
5iZfKj    3    45    1.0   1.0             4       2     # A2
5iZfKj    4    43    2.0   2.0             4       0     # G2
```

## RLS / Vertrag
- `anon` nur **SELECT** auf `song_intro_public`. Keine Schreibpfade.
- Quelle der Wahrheit: eure Noten/GP-Files. Nur die ersten Töne nötig, nicht der
  ganze Song.
- Leeres Ergebnis für einen Song = (noch) kein Anfang hinterlegt → die App
  überspringt/markiert ihn sauber.

## Was BassTrainer damit tut
- Songtitel anzeigen (zufällig aus Setlist/Repertoire), **Metronom-Einzähler**
  im Songtempo (`songs.bpm`).
- Soll-Anschlagzeiten = `beat × 60 / bpm`.
- Mikrofon (bestehende Pitch-Erkennung) misst Tonhöhe + Onset und bewertet:
  - **Tonhöhe** primär nach Tonname (oktav-tolerant — tiefe Basslagen sind in
    der Erkennung oktav-wackelig), exakte Oktave als Bonus.
  - **Rhythmus** als Abweichung zum Soll-Schlag (ms), wie in „Oktaven nach
    Metronom".
- Alles read-only.

## Offen / abzustimmen
- Format final **MIDI** ok, oder lieber Notennamen (`"E1"`) zusätzlich? (MIDI
  reicht der App; Notennamen wären nur Bonus für eure Pflege.)
- Reicht eine **monophone** Anfangslinie (ein Ton pro `beat`)? Doppelgriffe/Akkorde
  bräuchten ein anderes Bewertungsmodell — fürs Erste nehme ich monophon an.
