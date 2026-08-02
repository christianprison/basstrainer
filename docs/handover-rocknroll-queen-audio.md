# Übergabe: „Rock‘n‘Roll Queen" spielt kein Playback

**Status:** Daten-/Storage-Problem in Supabase. Kein App-Fehler. App ist dort read-only
(kein `service_role`) — Fix muss über den Kurator/lighting.ai erfolgen.

## Symptom
- Song „Rock‘n‘Roll Queen" (Subways) zeigt das Noten-Icon, aber der Play-along-Track lädt nicht.
- Alle anderen Songs spielen normal.

## Ursache (verifiziert)
- song_id: **`Pol09a`**
- Tabelle `audio_assets`, Zeile mit `bar_num = null` (Full-Song):
  `storage_path = audio/Rock‘n‘Roll Queen/Rock‘n‘Roll Queen - Full Song.mp3`
- Der Pfad enthält das typografische Zeichen **`‘` (U+2018)** statt eines normalen Apostrophs.
- Supabase Storage lässt dieses Zeichen im Object-Key **nicht** zu:
  `GET .../object/public/snippets/audio/Rock‘n‘Roll Queen/...`
  → `HTTP 400 {"error":"InvalidKey","message":"Invalid key: audio/Rock‘n‘Roll Queen/..."}`
- Kontrolle: „Animal" (`audio/Animal/Animal - Full Song.mp3`, reines ASCII) → `HTTP 200`, spielt.
- Scan aller 533 `audio_assets`-Zeilen: **nur diese eine** hat Nicht-ASCII im Pfad.

## Warum die App nichts tun kann
- Playback baut immer `…/storage/v1/object/public/snippets/<storage_path>`.
- Ein serverseitig ungültiger Key lässt sich clientseitig nicht „reparieren".
- Das Noten-Icon bedeutet nur „Pfad in DB vorhanden", nicht „Datei ladbar".

## Fix (Kurator)
1. Full-Song-Datei unter einem **gültigen ASCII-Key** im Bucket `snippets` ablegen, z. B.:
   `audio/Rock'n'Roll Queen/Rock'n'Roll Queen - Full Song.mp3` (normaler Apostroph `'`).
2. In `audio_assets` (song_id `Pol09a`, Zeile `bar_num = null`) `storage_path` auf **genau**
   diesen Key setzen.

## Offen / zu prüfen
- Die Varianten mit normalem Apostroph liefern aktuell ebenfalls 400 → die Datei liegt
  vermutlich noch gar nicht unter einem gültigen Key im Bucket. Listing per public/anon-Key
  ist gesperrt, der tatsächliche Upload-Name ist von außen nicht sichtbar — Kurator muss den
  realen Object-Namen im Storage gegenprüfen und Pfad + Datei aufeinander abstimmen.
- Empfehlung: künftige `storage_path`-Einträge auf reine ASCII-Zeichen normalisieren
  (typografische Anführungszeichen/Apostrophe aus Songtiteln nicht in Keys übernehmen).
