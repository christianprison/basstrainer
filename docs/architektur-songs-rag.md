# Architekturentwurf: Songs, Proberaummitschnitte & RAG

> **Status:** Entwurf (v1) – zur Verfeinerung in der lightning.AI-Umgebung.
> **Kontext:** BassTrainer Web-App (Next.js 14 App Router, React 19, TypeScript, Vercel).
> **Ziel:** Audio-Aufnahmen (Songs zum Mitspielen + Proberaummitschnitte) zentral speichern,
> in der App abspielbar machen und perspektivisch durchsuchbar via RAG.

---

## 1. Zielbild in einem Satz

Audiodateien liegen in **Object Storage**, ihre Metadaten in **Postgres**, und für die spätere
semantische Suche werden **Transkripte/Analysen als Embeddings** im selben Postgres (`pgvector`)
gehalten. Die Next.js-App liest Metadaten über serverseitige Routes und streamt das Audio per
signierter URL direkt aus dem Storage.

---

## 2. Leitprinzipien

1. **Audio nie als BLOB in die SQL-Datenbank.** Große Binärdateien gehören in Object Storage;
   die DB hält nur den Pfad/Key und Metadaten.
2. **Eine Datenstruktur für alles.** „Alle Songs", „Aktuelle Playlist" und „Proberaummitschnitte"
   sind dieselbe Entität (`recordings`) mit unterschiedlichen Attributen – kein doppeltes Schema.
3. **RAG-ready, aber nicht RAG-aktiv.** Das Schema enthält von Anfang an die Felder für Embeddings;
   die Pipeline wird erst später eingeschaltet. So bleibt die spätere Erweiterung billig.
4. **v0.app-Sync-resistent.** Die App wird laut `CLAUDE.md` über v0.app gesynct. DB-Anbindung und
   Songs-Feature werden so gekapselt (eigene Module/Ordner), dass ein Sync sie möglichst nicht
   überschreibt.
5. **Secrets nur serverseitig.** Service-Role-Keys und LLM-API-Keys laufen ausschließlich in
   Server-Code (API-Routes / Server Actions), niemals im Browser-Bundle.

---

## 3. Technologie-Empfehlung

**Supabase** als zentrale Plattform, weil es alle Bausteine in einem Produkt bündelt:

| Baustein            | Lösung                          | Zweck                                              |
|---------------------|---------------------------------|----------------------------------------------------|
| Metadaten-DB        | Supabase **Postgres**           | Songs, Playlists, Mitschnitte, Sessions            |
| Vektor-Suche (RAG)  | **pgvector** (in Postgres)      | Embeddings der Transkripte/Analysen                |
| Audio-Dateien       | Supabase **Storage** (S3-komp.) | Originaldateien, Streaming via signierte URLs      |
| Zugriffsschutz      | Supabase **Auth** + RLS         | Private Mitschnitte, geteilte Songs                |
| Region              | **EU (Frankfurt)**              | DSGVO-Konformität                                  |

### Alternativen (bewusst dokumentiert)
- **Neon (Postgres+pgvector) + Vercel Blob** – Vercel-nativ, DB-Branching, aber zwei Anbieter,
  kein integriertes Auth.
- **Cloudflare R2 + Postgres** – kein Egress-Entgelt beim Storage, mehr Eigenbau.
- **Self-hosted Postgres + MinIO** – nur bei bewusstem Wunsch nach voller Kontrolle (Overkill für
  ein Hobby-/Vereinsprojekt).

> Empfehlung bleibt **Supabase** für den geringsten Integrationsaufwand bei diesem Stack.

---

## 4. Systemüberblick

```
┌──────────────────────────────────────────────────────────────────────┐
│                          Browser (Next.js Client)                      │
│   - Songs-UI: "Alle Songs" / "Aktuelle Playlist"                       │
│   - Audio-Player (streamt via signierter URL)                          │
│   - Anon-Key (nur lesend, durch RLS abgesichert)                       │
└───────────────┬───────────────────────────────────┬──────────────────┘
                │ API-Routes / Server Actions        │ signierte URL
                ▼                                     ▼
┌──────────────────────────────┐        ┌────────────────────────────────┐
│   Next.js Server (Vercel)    │        │     Supabase Storage           │
│   - Service-Role-Key (secret)│◄──────►│     Bucket: recordings (privat)│
│   - Upload/CRUD/RAG-Queries  │        └────────────────────────────────┘
└───────────────┬──────────────┘
                │ SQL
                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                       Supabase Postgres (EU)                           │
│   recordings | playlists | playlist_items | transcripts(+embedding)    │
│   Extension: pgvector                                                  │
└──────────────────────────────────────────────────────────────────────┘
                ▲
                │ (asynchron, später)
┌──────────────────────────────────────────────────────────────────────┐
│            RAG-Ingestion (Whisper-Transkription + Embeddings)          │
│            z. B. als Edge Function / Cron / lightning.AI-Job           │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 5. Datenmodell

```sql
-- Extension einmalig aktivieren
create extension if not exists vector;

-- Jede Aufnahme: Song zum Mitspielen ODER Proberaummitschnitt
create table recordings (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  kind          text not null check (kind in ('song','rehearsal')),
  storage_path  text not null,            -- Key im Storage-Bucket
  duration_sec  int,
  recorded_at   timestamptz,
  music_key     text,                     -- Tonart, z. B. "Am"
  bpm           int,
  notes         text,
  created_at    timestamptz not null default now()
);

-- Playlists; genau eine ist "aktuell"
create table playlists (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  is_current  boolean not null default false,
  created_at  timestamptz not null default now()
);

-- nur EINE aktuelle Playlist erlauben
create unique index one_current_playlist
  on playlists (is_current) where is_current;

-- Zuordnung Song <-> Playlist inkl. Reihenfolge
create table playlist_items (
  playlist_id   uuid not null references playlists(id) on delete cascade,
  recording_id  uuid not null references recordings(id) on delete cascade,
  position      int not null,
  primary key (playlist_id, recording_id)
);

-- RAG: Transkript-/Analyse-Chunks mit Embedding (erst später befüllt)
create table transcripts (
  id            uuid primary key default gen_random_uuid(),
  recording_id  uuid not null references recordings(id) on delete cascade,
  chunk_text    text not null,
  ts_start      numeric,                  -- Sekunde im Audio
  ts_end        numeric,
  embedding     vector(1536),             -- Dimension je nach Embedding-Modell
  created_at    timestamptz not null default now()
);

-- Vektor-Index für Ähnlichkeitssuche
create index transcripts_embedding_idx
  on transcripts using ivfflat (embedding vector_cosine_ops) with (lists = 100);
```

**Abbildung der Anforderungen:**
- *Alle Songs* → `select * from recordings where kind = 'song'`
- *Aktuelle Playlist* → `recordings` über `playlist_items` der Playlist mit `is_current = true`,
  sortiert nach `position`
- *Proberaummitschnitte* → `recordings where kind = 'rehearsal'`
- *RAG* → Embedding-Suche in `transcripts`, dann Join auf `recordings`

---

## 6. App-Integration (Next.js)

### Vorgeschlagene Dateistruktur (gekapselt, v0-sync-schonend)
```
lib/
  supabase/
    client.ts          # Browser-Client (Anon-Key)
    server.ts          # Server-Client (Service-Role, nur serverseitig)
  songs/
    types.ts           # Recording, Playlist, ...
    queries.ts         # Datenzugriff (serverseitig)
app/
  songs/
    page.tsx           # Songs-Bereich mit Tabs "Alle Songs" / "Aktuelle Playlist"
  api/
    songs/route.ts     # GET Liste
    playlist/route.ts  # GET/PUT aktuelle Playlist
    recordings/[id]/stream-url/route.ts   # signierte URL erzeugen
components/
  songs/
    songs-view.tsx     # Tabs + Liste
    audio-player.tsx   # Player (Play/Pause, Tempo, Loop optional)
```

### Streaming-Fluss
1. Client fragt `/api/recordings/[id]/stream-url` an.
2. Server erzeugt mit Service-Role eine **kurzlebige signierte URL** aus dem privaten Bucket.
3. Client setzt die URL als `src` des `<audio>`-Elements → spielt direkt aus Storage.

### Env-Variablen
```
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...        # nur Server, niemals NEXT_PUBLIC_
# später für RAG:
OPENAI_API_KEY=...                   # oder anderer Embedding-/LLM-Anbieter
```
Diese Werte sowohl lokal (`.env.local`) als auch in **Vercel** (Production + Preview) hinterlegen.

---

## 7. RAG-Pipeline (Phase 2)

Ablauf pro Mitschnitt – läuft **asynchron**, nicht im Request-Pfad der App:

1. **Upload** → Datei in Storage, Zeile in `recordings`.
2. **Transkription** → Whisper (oder vergleichbar) erzeugt Text mit Zeitstempeln.
   Bei rein instrumentalem Material zusätzlich/stattdessen manuelle Notizen, Akkorde, Tags.
3. **Chunking** → Transkript in sinnvolle Abschnitte (z. B. 30–60 s) teilen.
4. **Embedding** → je Chunk einen Vektor erzeugen → in `transcripts.embedding` speichern.
5. **Query** → Nutzerfrage einbetten → Cosine-Ähnlichkeitssuche → Top-Treffer als Kontext an ein
   LLM → Antwort mit Verweis auf konkrete Aufnahme + Zeitstempel.

**Beispiel-Query:** *„In welchem Mitschnitt haben wir das Reggae-Stück in A-Moll gejammt?"*
→ liefert Treffer aus `recordings` inkl. Sprungmarke im Audio.

**Wo ausführen?** Edge Function / Cron-Job / dedizierter Worker – oder genau in der
**lightning.AI-Umgebung**, die sich für die Transkriptions-/Embedding-Last gut eignet.

---

## 8. Sicherheit & Datenschutz

- **RLS aktivieren** auf allen Tabellen; öffentliche Songs lesbar, Mitschnitte nur für berechtigte
  Nutzer.
- **Bucket privat**, Zugriff ausschließlich über kurzlebige signierte URLs.
- **Service-Role-Key** nur serverseitig; nie im Client-Bundle.
- **EU-Region** für DSGVO; Aufnahmen mit Personen (Bandkollegen) = personenbezogene Daten →
  Zugriff bewusst einschränken.

---

## 9. Migration der bestehenden Aufnahmen (lightning.AI → Supabase)

Einmaliger Transfer, offen im Detail:
1. Dateien aus der lightning.AI-Umgebung exportieren (Download-Links oder lokaler Export).
2. Skript: pro Datei → in Storage hochladen → `recordings`-Zeile anlegen (Titel, Dauer, Datum).
3. Optional direkt anschließend die RAG-Ingestion (Schritt 7.2–7.4) anstoßen.

> Offen: Wie genau die Dateien aus lightning.AI bereitgestellt werden (API/Token/Export). Das ist
> der einzige Schritt, der Zugang zur lightning.AI-Seite braucht.

---

## 10. Umsetzungsphasen

| Phase | Inhalt | Ergebnis |
|------|--------|----------|
| 0 | Supabase-Projekt (EU), Bucket, Env-Vars in Vercel | Infrastruktur steht |
| 1 | Schema/Migration anlegen (Abschnitt 5) | DB bereit |
| 2 | SDK-Anbindung + API-Routes (Abschnitt 6) | App liest/schreibt Metadaten |
| 3 | Songs-UI „Alle Songs" / „Aktuelle Playlist" + Player | Mitspielen funktioniert |
| 4 | Upload-/Migrations-Skript | Aufnahmen in Supabase |
| 5 | RAG-Ingestion + Such-UI | Semantische Suche aktiv |

---

## 11. Offene Punkte / Entscheidungen für die Verfeinerung

- [ ] Embedding-Modell und damit Vektor-**Dimension** festlegen (Schema-`vector(N)` anpassen).
- [ ] Transkription für rein instrumentale Mitschnitte: Whisper sinnvoll oder lieber
      manuelle Tags/Akkord-Erkennung?
- [ ] Auth nötig (privat) oder bleibt alles öffentlich lesbar?
- [ ] Wo läuft die RAG-Ingestion (Edge Function vs. lightning.AI-Job)?
- [ ] Audioformat/Transcoding (z. B. einheitlich zu `.mp3`/`.m4a` für Browser-Kompatibilität)?
- [ ] Wie kommen die Bestandsaufnahmen aus lightning.AI heraus (Export-Weg)?
