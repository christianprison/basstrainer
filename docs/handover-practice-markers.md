# Übergabe an die lighting.ai-Session — Schreibzugriff für private Übe-Marker (BassTrainer)

## TL;DR
BassTrainer (native iPad-App) soll **private Übe-Marker** speichern: markierte
Taktbereiche („problematische Stellen") mit Grund, zum späteren Loop-Üben.
**Pro Nutzer privat**, niemand sieht fremde Marker. Umsetzung über
**Supabase Anonymous Auth + RLS auf `auth.uid()`**. Sonst bleibt BassTrainer
**read-only** auf allem anderen. Der `service_role`-Key wird **nie** im Client
verwendet.

## Was du (lighting.ai) bitte einrichtest

### 1) Anonyme Anmeldung aktivieren
Supabase → **Authentication → Providers → „Anonymous sign-ins" = ON**.
(BassTrainer meldet jedes Gerät einmal anonym an, ohne Login-UI, und schreibt
nur mit dem so erhaltenen JWT.)

### 2) Tabelle + RLS (als Migration, z. B. `0003_practice_markers.sql`)

```sql
create table public.practice_markers (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid(),
  song_id     text not null references public.songs(id) on delete cascade,
  start_bar   int  not null,
  end_bar     int  not null,
  reason      text not null check (reason in ('speed','precision','timing','shift','other')),
  created_at  timestamptz not null default now()
);

create index practice_markers_user_song_idx
  on public.practice_markers (user_id, song_id);

alter table public.practice_markers enable row level security;

-- Jeder sieht/ändert ausschließlich seine eigenen Marker:
create policy markers_select on public.practice_markers
  for select using (auth.uid() = user_id);
create policy markers_insert on public.practice_markers
  for insert with check (auth.uid() = user_id);
create policy markers_update on public.practice_markers
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy markers_delete on public.practice_markers
  for delete using (auth.uid() = user_id);
```

## Was BassTrainer damit tut (Vertrag)
- **Auth:** einmalig `POST /auth/v1/signup` (anonymous) mit Header
  `apikey: <anon>` → speichert `access_token` + `refresh_token` lokal, erneuert
  per `/auth/v1/token?grant_type=refresh_token`.
- **Schreiben/Lesen der Marker:** `/rest/v1/practice_markers` mit
  `apikey: <anon>` **und** `Authorization: Bearer <access_token>` (User-JWT,
  nicht der bloße anon-Key). `user_id` wird serverseitig per
  `default auth.uid()` gesetzt — der Client schickt es nicht.
- **Alles andere bleibt read-only** (Songs, Setlist, Timeline, Lyrics, Audio).
- **Spaltensemantik:** `reason ∈ {speed, precision, timing, shift, other}` =
  Geschwindigkeit / Präzision / Timing / Lagenwechsel / Sonstiges.
  `start_bar`/`end_bar` = Taktnummern (1-basiert, passend zu
  `song_timeline_public.bar_num`).

## Hinweise
- **Anon-User sammeln sich** in `auth.users` an (ein Datensatz pro Gerät/
  Neuinstallation) — normal; optional später aufräumen.
- **Kein Cross-Device-Sync:** Die Identität hängt am Gerät. Wenn du Marker
  später über mehrere Geräte teilen willst, bräuchte es echtes Login
  (Magic-Link) — kann man additiv nachrüsten, Tabelle/RLS bleiben gleich.
- Bitte die Tabelle in die regulären Migrationen aufnehmen, damit sie bei
  künftigen Syncs erhalten bleibt.

## Danach (BassTrainer-Seite)
Sobald Tabelle + Anonymous-Auth stehen, baue ich in der App: anonyme Anmeldung
(REST, kein JS-SDK), Token-Speicherung/-Refresh, und ersetze den lokalen
Marker-Store durch DB-Lesen/-Schreiben (mit lokalem Cache als Offline-Fallback).
Vorhandene lokale Marker werden einmalig hochmigriert.
