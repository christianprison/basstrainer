# TestFlight-Pipeline (fastlane + GitHub Actions)

Diese Pipeline baut die iPad-App, signiert sie via **fastlane match** und lädt sie
bei jedem Versions-Tag (`v*`) nach **TestFlight** hoch.

Workflow: [`.github/workflows/testflight.yml`](../../.github/workflows/testflight.yml)
Lane: `fastlane beta` (siehe `Fastfile`)

---

## Was die Pipeline tut

1. macOS-Runner, Xcode auswählen, XcodeGen + fastlane installieren
2. `xcodegen generate` → `BassTrainer.xcodeproj` aus `project.yml`
3. `match` holt Distributions-Zertifikat + Provisioning-Profil (readonly)
4. `gym` archiviert & exportiert die `.ipa` (manuelles Signing, App-Store-Profil)
5. `pilot` lädt nach TestFlight hoch

Version: Marketing-Version aus dem Tag (`v1.2.3` → `1.2.3`), Build-Nummer aus der
GitHub-Run-Nummer (monoton steigend – das verlangt TestFlight).

---

## Einmaliges Setup (musst du selbst machen — Apple-Seite)

### 1. Voraussetzungen
- **Apple Developer Program** (99 $/Jahr), aktiv.
- App in **App Store Connect** anlegen mit Bundle-ID `de.prisons.basstrainer`.
- Ein **separates, privates Git-Repo** für die match-Zertifikate (z.B. `apple-certificates`).
  Bewusst **generisch** benennen: Das Distributions-Zertifikat ist account-weit und wird von
  allen deinen Apps geteilt; dieses Repo kann die Zertifikate + Profile mehrerer Apps halten.

### 2. App Store Connect API-Key
App Store Connect → *Users and Access* → *Integrations* → *App Store Connect API*
→ neuen Key mit Rolle **App Manager** erzeugen. Du erhältst:
- **Key ID**
- **Issuer ID**
- die **`.p8`-Datei** (nur einmal herunterladbar!)

### 3. match einmalig lokal initialisieren
Auf einem Mac mit Zugang zum Developer-Account:

```bash
cd BassTrainer-iPad
bundle install
export MATCH_GIT_URL="git@github.com:<dein-user>/apple-certificates.git"
export MATCH_PASSWORD="<eine-starke-passphrase>"   # merken! = Verschlüsselung
bundle exec fastlane match appstore
```

Das erzeugt Zertifikat + Profil, verschlüsselt sie und legt sie im certs-Repo ab.

---

## GitHub-Secrets (Repo → Settings → Secrets and variables → Actions)

| Secret | Inhalt |
|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID aus Schritt 2 |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID aus Schritt 2 |
| `APP_STORE_CONNECT_API_KEY` | Inhalt der `.p8`, **Base64-codiert** (`base64 -i AuthKey_XXXX.p8 \| pbcopy`) |
| `APPLE_TEAM_ID` | 10-stellige Team-ID (Developer-Portal → Membership) |
| `MATCH_GIT_URL` | URL des certs-Repos (HTTPS-Form, z.B. `https://github.com/<user>/apple-certificates.git`) |
| `MATCH_PASSWORD` | dieselbe Passphrase wie bei Schritt 3 |
| `MATCH_GIT_TOKEN` | Roher Fine-grained PAT (`github_pat_…`) mit **Contents: Read** auf das certs-Repo. Kein Base64. |

> `MATCH_GIT_TOKEN` erlaubt dem Runner, das private certs-Repo zu klonen: Der Workflow setzt
> damit `git config --global url."https://x-access-token:<TOKEN>@github.com/".insteadOf …`,
> sodass match das Repo authentifiziert klont. Token-Wert wird im Log maskiert.

---

## Auslösen

```bash
git tag v1.0.1
git push origin v1.0.1
```

→ Workflow „TestFlight" startet, Build landet nach ein paar Minuten in App Store Connect
und (nach Apples Processing) in TestFlight.

---

## Hinweise / Stolpersteine
- **Erster Lauf scheitert oft an Kleinigkeiten** (Bundle-ID nicht registriert, Key-Rolle
  zu niedrig, Team-ID falsch). Logs im Actions-Tab lesen – die Fehler sind meist eindeutig.
- **Build-Processing dauert**: `pilot` wartet bewusst nicht (`skip_waiting_for_build_processing`).
  Der Build erscheint erst nach Apples Verarbeitung in TestFlight.
- **Export-Compliance / Verschlüsselung**: Beim ersten TestFlight-Build fragt Apple ggf. nach
  Export-Compliance. Für eine App ohne eigene Kryptografie kann man im Info.plist
  `ITSAppUsesNonExemptEncryption = false` setzen, um die Rückfrage zu vermeiden.
- **macOS-Runner-Minuten** zählen bei privaten Repos 10× – Tag-Trigger hält das gering.
- **Zertifikat-Ablauf**: Distributions-Zertifikate laufen jährlich ab. Dann lokal erneut
  `bundle exec fastlane match appstore` (ohne readonly) ausführen.
