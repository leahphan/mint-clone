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

## Scrubbing bank CSVs

`bin/scrub-bank-csv` makes a copy of a real bank CSV that is safe to share or to use as a test
fixture. It's a development-only tool: it runs entirely on your machine (no network calls), never
modifies the input file, and isn't loaded by the app.

```bash
bin/scrub-bank-csv --preview ~/Downloads/accountactivity.csv   # show the detected structure; writes nothing
bin/scrub-bank-csv ~/Downloads/accountactivity.csv             # writes tmp/scrubbed-bank-data/accountactivity-scrubbed.csv
bin/scrub-bank-csv --strict --randomize-amounts --scrub-balances --shift-dates ~/Downloads/accountactivity.csv
```

By default dates, amounts, and running balances are kept exactly, along with the delimiter, quoting,
header, blank lines, line endings, row order, and duplicate rows. Descriptions keep their shape and
processor prefixes (`SQ *JOES CAFE TORONTO ON #0382` → `SQ *KAFU CAFE TORONTO ON #0382`,
`E-TRANSFER TO JOHN SMITH` → `E-TRANSFER TO TEST PERSON A`). Names, emails, phone numbers, postal
codes, and card, account, and reference numbers are replaced, the same way every time within one
file, so repeated merchants stay repeated.

| Flag | Effect |
| --- | --- |
| `--preview` | Print input/output paths, the detected structure, and what will be replaced. Writes nothing. |
| `--strict` | Also replace city and category words (`TORONTO`, `CAFE`), store numbers, and short reference codes. |
| `--randomize-amounts` | Scale each distinct amount (same amount → same new amount), keeping direction; recalculates balances. |
| `--scrub-balances` | Shift every running balance by one hidden offset, keeping the arithmetic. |
| `--shift-dates` | Move every date back by one hidden number of days, keeping formats and gaps. |

Output always goes to `tmp/scrubbed-bank-data/`, which is gitignored. Skim the output before sharing
it — the scrubber can't recognize every possible identifier. To commit a fixture, copy the
*scrubbed* file into `test/fixtures/files/`; never commit the original.
