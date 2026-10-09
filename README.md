# Mint clone

A personal finance app inspired by Mint.com. Setup, commands and conventions are in [CLAUDE.md](CLAUDE.md).

## Phone QA workflow

Branches: `claude/<feature>` (Claude's work) → `staging` (ready for manual QA) → `master` (approved).
One permanent QA Codespace runs `staging`.

### Normal workflow

1. Ask Claude to build the feature.
2. Ask Claude to put it on staging.
3. Start (or restart) the staging Codespace: github.com/codespaces → your staging Codespace.
4. Wait for automatic startup, about 1–2 minutes (longer if gems changed).
5. Open your bookmarked Rails URL in Safari.
6. QA manually.
7. If it's good, ask Claude to open a PR / merge the feature to master.

On every start, the Codespace resets itself to `origin/staging`, installs gems if needed, runs
`bin/rails db:prepare` (migrates; keeps your QA data) and starts Rails in the background.

**Don't edit code in the QA Codespace.** Uncommitted changes and local commits on `staging` there
are discarded on every start. Untracked files (`log/`, `tmp/`, `storage/`, `.env*`) and the database are kept.

### If the Codespace is already running

```bash
bin/qa-refresh
```

### Debugging

- Startup log: `log/codespace.log` (Rails request log: `log/development.log`)
- Is Rails up? `curl -sI localhost:3000` should print `HTTP/1.1 200 OK`
- Restart Rails: `bin/qa-refresh`
- Your URL (bookmark this once): `echo https://$CODESPACE_NAME-3000.$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN`,
  also printed at the end of `log/codespace.log`. The pattern is
  `https://<codespace-name>-3000.app.github.dev`. It belongs to the Codespace, so it stays the same
  as long as you keep this Codespace.

Port 3000 is private: it opens only for you, signed in to GitHub in that browser. Secrets
come from Codespaces secrets (github.com → Settings → Codespaces), never from the repo.

## CSV import

Upload a bank or credit card CSV export on an account's Import page. Common layouts are
recognized automatically; anything uncertain shows a preview where you confirm or correct the
columns, and a confirmed layout is remembered for that account.

- Rows with a running balance (e.g. TD exports) are deduplicated across overlapping exports. If
  one matches a transaction entered by hand or imported without a balance, it's imported and
  flagged as a possible duplicate. (Rare exception: an identical charge-and-reversal repeated on
  the same day, landing on the same balance, can look like one already imported.)
- Rows without one only dedupe re-uploads of the same file; matches across files are imported
  and flagged as possible duplicates, never dropped. Reliable overlap dedupe needs a balance or a
  transaction ID, so this is a known limitation for such formats.
- Unconfirmed uploads are deleted after 24 hours: on the next upload, on every QA Codespace start,
  hourly in production, or with `bin/rails imports:purge_pending`.
- AI schema detection is off unless `AI_CSV_SCHEMA_ENABLED=true` (uses the `OLLAMA_*` settings).
  It only sees a redacted description of the file: column statistics and cell kinds, never values.
