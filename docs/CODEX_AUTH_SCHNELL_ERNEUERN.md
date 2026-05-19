# Codex-Auth auf Railway schnell erneuern

So erneuerst du die OpenAI‑Codex‑Anmeldung für Paperclip (**`codex_local`**) auf Railway, ohne `OPENAI_API_KEY` zu setzen — nur Datei‑Auth unter **`CODEX_HOME`** (Standard: **`/data/.codex/auth.json`**).

---

## Wann diese Anleitung zutrifft

- Meldungen wie **„refresh token was revoked“** oder Auth‑Probe schlägt fehl
- Du hast lokal bereits **`codex`** installiert (siehe [OPENAI_CODEX_RAILWAY.md](OPENAI_CODEX_RAILWAY.md))
- Railway: Paperclip-Service, Volume **`/data`**, **`CODEX_HOME=/data/.codex`**

---

## Schritt 1: Lokal neu einloggen (1–2 Minuten)

Im Terminal auf deinem Mac:

```bash
# Sicherstellen: richtiges codex (z. B. ~/.npm-global/bin)
which codex

codex logout
codex login
```

1. Terminal folgt den Anweisungen (Browser öffnet sich, oft **`localhost`**).
2. Nach **„Signed in to Codex“** die Seite schließen, zurück ins Terminal bis der Login dort fertig ist.
3. Prüfen:

```bash
ls -la ~/.codex/auth.json
```

**Niemals** `auth.json` ins Git kopieren oder in Chats/Changelog einfügen.

---

## Schritt 2: Auth ins Railway-Volume schreiben (ca. 1 Minute)

Im Projekt (Fork‑Repo), **`railway link`** auf Projekt → Environment → Service **„Paperclip“**:

```bash
cd /Pfad/zu/paperclip-railway-template

npx railway login          # nur falls noch nicht eingeloggt
npx railway link           # Projekt Beatles, Paperclip-Service

npx railway ssh -- mkdir -p /data/.codex

cat ~/.codex/auth.json | npx railway ssh -- tee /data/.codex/auth.json > /dev/null

npx railway ssh -- chmod 600 /data/.codex/auth.json
npx railway ssh -- chown node:node /data/.codex/auth.json
```

Kurzkontrolle (Zeilen nur, **keinen** Dateiinhalt posten):

```bash
wc -c ~/.codex/auth.json
npx railway ssh -- wc -c /data/.codex/auth.json
```

Beide **`wc`**-Werte sollten **gleich** sein.

SSH braucht einmal registrierten Key bei Railway — siehe [OPENAI_CODEX_RAILWAY.md § 3](OPENAI_CODEX_RAILWAY.md).

---

## Schritt 3: In Paperclip prüfen

1. **`https://<deine-paperclip-url>/`** öffnen
2. Agent mit Adapter **Codex (local)** öffnen
3. **Adapter environment check** → **Test now**

Erwartung: **Passed** (grün).

---

## Alternative ohne SSH-Kopie: `/setup`

Falls ihr **„Run Codex login“** auf **`/setup`** nutzt und der Flow im Browser/Container durchläuft, wird dort ebenfalls **`/data/.codex`** geschrieben — ohne Kopieren vom Mac.

---

## Wenn lokales `codex` nicht läuft (macOS)

- Installation mit **`--include=optional`** (Apple Silicon: `@openai/codex-darwin-arm64`).
- Bei **`EACCES`** bei globalem npm: Prefix **`~/.npm-global`** oder `sudo` bei Install — siehe Hauptdoku.

---

## Kurzfassung (Copy-Paste-Block)

```bash
codex logout && codex login
cat ~/.codex/auth.json | npx railway ssh -- tee /data/.codex/auth.json > /dev/null
npx railway ssh -- chmod 600 /data/.codex/auth.json
npx railway ssh -- chown node:node /data/.codex/auth.json
```

Danach im Paperclip-UI **Test now**.
