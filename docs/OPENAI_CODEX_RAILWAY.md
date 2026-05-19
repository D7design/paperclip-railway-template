# OpenAI Codex auf Railway mit Paperclip (`codex_local`)

Diese Anleitung beschreibt, wie Paperclip auf Railway mit dem **OpenAI Codex CLI** (`codex`) und dem Adapter **`codex_local`** betrieben wird — **ohne** `OPENAI_API_KEY`, **ohne** Cursor-Agent und **ohne** GitHub Copilot CLI.

Die Authentifizierung läuft über **Codex-Login-Dateien** (insbesondere `auth.json`) auf einem **persistenten Railway-Volume**.

**Auth erneuern (kurz):** [CODEX_AUTH_SCHNELL_ERNEUERN.md](CODEX_AUTH_SCHNELL_ERNEUERN.md).

---

## Zielbild

| Komponente | Wert / Verhalten |
|------------|------------------|
| Agent-Adapter in Paperclip | `codex_local` |
| CLI-Befehl | `codex` (npm-Paket `@openai/codex`) |
| Auth | Dateien unter `CODEX_HOME` (z. B. `auth.json`) |
| Persistentes Volume | Mount bei **`/data`** |
| Codex-Daten | **`/data/.codex`** (`CODEX_HOME=/data/.codex`) |
| Paperclip-Daten | `PAPERCLIP_HOME=/paperclip` (App-State; ggf. separates Volume) |
| API-Key | **Nicht** erforderlich für Codex |

---

## Voraussetzungen

- GitHub-Account mit Fork des Templates (z. B. `D7design/paperclip-railway-template`)
- [Railway](https://railway.com)-Projekt mit Postgres + Paperclip-Service
- Lokal: `codex login` einmal ausgeführt (`~/.codex/auth.json` vorhanden)
- Optional: [Railway CLI](https://docs.railway.com/cli/ssh) für SSH und Datei-Kopie

---

## 1. Repository vorbereiten

### 1.1 Fork & Klon

```bash
# Fork auf GitHub anlegen (Web UI oder gh)
gh repo fork Lukem121/paperclip-railway-template --clone

cd paperclip-railway-template
git remote -v
# origin → dein Fork
```

### 1.2 Relevante Code-Anpassungen (bereits im Fork `main`)

Diese Dateien sind für Codex auf Railway mit Volume unter `/data` ausgelegt:

| Datei | Zweck |
|-------|--------|
| `Dockerfile` | `ENV CODEX_HOME=/data/.codex`, global `npm i -g @openai/codex` |
| `scripts/entrypoint.sh` | `mkdir` + Rechte für `/data` / `CODEX_HOME` (Fallback) |
| `railway.toml` | `startCommand = "node /wrapper/src/server.js"` — **kein** `mkdir … && …` (siehe unten) |
| `src/server.js` | `ensureCodexHome()` beim Wrapper-Start; Setup-UI für Codex-Status |
| `.gitignore` | `.codex/`, `auth.json`, SQLite — **niemals** committen |
| `.env.example` | Dokumentation der Variablen |

**Warum kein `mkdir` in `railway.toml`?**  
Bei Dockerfile-Deployments wendet Railway den `startCommand` oft in **Exec-Form** an — **ohne Shell**. Dann gilt `mkdir -p … && node …` **nicht** als Shell-Kette: `&&` wird an `mkdir` übergeben und **Node startet nicht** → Healthcheck schlägt fehl (Deploy FAILED).

`/data/.codex` wird stattdessen durch:

1. `src/server.js` → **`ensureCodexHome()`** (nach Volume-Mount, beim Node-Start)
2. `scripts/entrypoint.sh` → **`mkdir`** (Fallback; kann vor dem Mount laufen — deshalb 1. nötig)

Das Docker **`CMD`** kann optional `sh -c 'mkdir … && node …'` enthalten; Railway **`startCommand` überschreibt** das `CMD`, nicht den Entrypoint.

**Variablen:** Start-Befehl in Railway **nicht** manuell mit `mkdir … && …` überschreiben — gleiches Problem.

### 1.3 Commits pushen

```bash
git push origin main
```

---

## 2. Railway konfigurieren

### 2.1 Service mit Fork verbinden

1. Railway → Projekt → Service **Paperclip** → **Settings** → **Source**
2. Repo: **`dein-user/paperclip-railway-template`**, Branch **`main`**
3. Falls die Suche leer ist: [GitHub App für Railway konfigurieren](https://github.com/settings/installations) → Repository freigeben

**Hinweis:** Eine separate „Codex-Check“-Hilfs-App misst oft **einen anderen Container** ohne Template-Image — nicht als alleinige Wahrheit nutzen.

### 2.2 Volume

1. Service **Paperclip** → **Volumes**
2. Volume anlegen / verbinden mit Mount-Pfad: **`/data`**
3. Ohne Volume gehen Codex-Auth-Daten bei Redeploy verloren

### 2.3 Umgebungsvariablen (Paperclip-Service)

Pflicht (siehe auch `.env.example`):

| Variable | Wert |
|----------|------|
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` |
| `BETTER_AUTH_SECRET` | mind. 32 Zeichen (Secret) |
| `HOST` | `0.0.0.0` |
| `PORT` | `3100` |
| `SERVE_UI` | `true` |
| `PAPERCLIP_HOME` | `/paperclip` |
| `CODEX_HOME` | `/data/.codex` |
| `PAPERCLIP_DEPLOYMENT_MODE` | `authenticated` |
| `PAPERCLIP_DEPLOYMENT_EXPOSURE` | `private` |
| `PAPERCLIP_PUBLIC_URL` | `https://${{Paperclip.RAILWAY_PUBLIC_DOMAIN}}` |
| `BETTER_AUTH_BASE_URL` | wie `PAPERCLIP_PUBLIC_URL` |

**Nicht setzen für Codex:**

- `OPENAI_API_KEY` — nicht nötig bei File-Auth

Optional:

- `ANTHROPIC_API_KEY` — nur für Claude-Adapter

### 2.4 Netzwerk

- HTTP-Proxy Port: **3100**
- Healthcheck: **`/setup/healthz`**

### 2.5 Deploy

Push auf `main` oder manuell **Redeploy**. Der Docker-Build dauert oft **15–30+ Minuten** (Paperclip wird im Image gebaut).

---

## 3. Codex-Authentifizierung ins Volume legen

### 3.1 Lokal einloggen (einmalig)

```bash
codex login
ls -la ~/.codex/auth.json
```

### 3.2 `auth.json` auf Railway kopieren

**Variante A: Railway CLI + SSH (empfohlen)**

```bash
cd paperclip-railway-template
npx railway login
npx railway link   # Projekt + Service „Paperclip“

# Verzeichnis sicherstellen
npx railway ssh -- mkdir -p /data/.codex

# auth.json kopieren (Rohdatei, kein base64!)
cat ~/.codex/auth.json | npx railway ssh -- tee /data/.codex/auth.json > /dev/null

# Rechte
npx railway ssh -- chmod 600 /data/.codex/auth.json
npx railway ssh -- chown node:node /data/.codex/auth.json

# Prüfen (Größe sollte mit lokal übereinstimmen)
wc -c ~/.codex/auth.json
npx railway ssh -- wc -c /data/.codex/auth.json
```

**Variante B: Setup-UI**

1. App-URL öffnen → **`/setup`**
2. **Run Codex login** (Device-/OAuth-Flow im Container)
3. Codex-Status sollte grün werden

### 3.3 SSH-Key für Railway (einmalig)

Falls `railway ssh` nach Keys fragt:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
npx railway ssh keys add --key ~/.ssh/id_ed25519.pub --name "Mac"
```

Bei `Host key verification failed` nach Railway-Update:

```bash
ssh-keygen -R ssh.railway.com
ssh-keyscan -t ed25519 ssh.railway.com >> ~/.ssh/known_hosts
```

---

## 4. Paperclip: Agent mit `codex_local`

1. Als Admin einloggen (`/setup` → Admin-Invite, falls noch nicht geschehen)
2. Agent anlegen oder bearbeiten
3. Adapter: **`codex_local`**
4. Agent-Run testen

Paperclip-Dokumentation: [Codex Local Adapter](https://paperclip.inc/docs/adapters/codex-local)

---

## 5. Verifikation (Checkliste)

### Im Container (SSH)

```bash
npx railway ssh -- test -x /wrapper/entrypoint.sh && echo "Template ok"
npx railway ssh -- env | grep -E '^(CODEX_HOME|PAPERCLIP_HOME)='
npx railway ssh -- ls -la /data/.codex/
npx railway ssh -- which codex
npx railway ssh -- codex --version
```

Erwartung:

- `CODEX_HOME=/data/.codex`
- `PAPERCLIP_HOME=/paperclip`
- `/data/.codex/auth.json` vorhanden, Mode `600`, Owner `node`
- `codex` unter `/usr/local/bin/codex`

### Im Browser

- `https://<deine-app>/setup` → **Codex: authenticated**
- App unter `/` erreichbar

---

## 6. Container-Start (zum Verständnis)

```text
Railway startet Container
    → ENTRYPOINT /wrapper/entrypoint.sh (root: mkdir, chown)
    → setpriv → User node
    → startCommand (Railway): node /wrapper/src/server.js
    → server.js: ensureCodexHome()
    → Paperclip intern + Proxy auf PORT 3100
```

`railway.toml` überschreibt nur das Docker-`CMD`, **nicht** den `ENTRYPOINT`.

---

## 7. Sicherheit

| Regel | Grund |
|-------|--------|
| **Nie** `auth.json`, `.codex/` ins Git | Tokens/Session-Daten |
| **Nie** Secrets in Logs oder Commits | Leak-Risiko |
| Auth nur ins **Volume** kopieren | Persistent, privat zum Projekt |
| `.gitignore` prüfen | `auth.json`, `**/.codex/`, `*.sqlite` |

---

## 8. Fehlerbehebung

| Symptom | Ursache | Lösung |
|---------|---------|--------|
| Deploy FAILED, Healthcheck | `startCommand` mit `mkdir && node` | Nur `node /wrapper/src/server.js`; Codex-Verzeichnis legt `ensureCodexHome()` an |
| `/data/.codex` fehlt | Volume-Mount nach Entrypoint | Redeploy mit aktuellem `main`; `ensureCodexHome()` |
| `codex: not found` | Falsches Image / anderer Service | SSH im **Paperclip**-Service; `which codex` |
| Codex-Check-URL rot, Paperclip ok | Separater Hilfs-Container | Nur Paperclip-SSH / `/setup` nutzen |
| `PAPERCLIP_HOME=NOT SET` | Kein Template-Image | Repo/Branch/Deploy prüfen |
| Repo-Suche leer in Railway | GitHub App ohne Repo-Zugriff | Railway App → `paperclip-railway-template` freigeben |
| `GitHub Repo not found` + Branch | Branch `production` vs. `main` | Branch auf **`main`** stellen |
| Codex-Warnung „path does not exist“ | Kein `mkdir` auf Volume | Abschnitt 3.2 |
| Auth ok, Agent scheitert | Falscher Adapter | `codex_local` wählen |

---

## 9. Reproduktion von Null (Kurzablauf)

1. Fork `Lukem121/paperclip-railway-template` → Klon
2. Sicherstellen, dass `main` die Codex-Anpassungen enthält (oder dieses Dokument + Commits nachziehen)
3. Railway: Postgres + Paperclip, Repo = Fork, Branch `main`
4. Volume **`/data`**, Variablen wie Abschnitt 2.3
5. Deploy abwarten (langer Build)
6. Lokal `codex login` → `auth.json` nach `/data/.codex/` kopieren (Abschnitt 3.2)
7. `/setup` prüfen → Admin → Agent `codex_local`
8. Optional: Upstream-Updates per `git fetch upstream && git merge upstream/main`

---

## 10. Upstream-Template aktualisieren

```bash
git remote add upstream https://github.com/Lukem121/paperclip-railway-template.git
git fetch upstream
git merge upstream/main
# Konflikte in Dockerfile, entrypoint.sh, server.js manuell lösen (Codex-Pfade behalten)
git push origin main
```

---

## GitHub CLI (`gh`) im Container — PRs durch Coding-Agenten

Das [Paperclip How-To „Connect an agent to a GitHub repo…“](https://docs.paperclip.ing/#/how-to/connect-agent-to-github/connect-an-agent-to-a-github-repo-and-have-it-open-prs) benötigt die **GitHub CLI** (`gh pr create`). Dieses Template installiert **`gh`** im Runtime-Image (Debian APT: [GitHub CLI](https://cli.github.com/)).

Damit **`git push`** und **`gh`** auf Railway funktionieren:

- Tokens **nicht** per `gh auth login` im Container erwarten → **Fine-grained PAT** oder **GitHub App**, als **Paperclip Secrets** gebunden auf `GITHUB_TOKEN` und `GH_TOKEN` im Coding-Agent (`secret_ref`; siehe externes How-To).
- **`cwd`** / Worktree-Pfade müssen für den **Linux-Pfad im Container** (z. B. unter **`/paperclip`**) gesetzt sein, nicht mit macOS-Pfaden aus der Doku 1:1 kopieren.

---

## Referenzen

- Template-Fork: `https://github.com/D7design/paperclip-railway-template`
- Original-Template: `https://github.com/Lukem121/paperclip-railway-template`
- Paperclip upstream: `https://github.com/paperclipai/paperclip`
- Codex CLI npm: `@openai/codex`
- Railway SSH: `https://docs.railway.com/cli/ssh`
