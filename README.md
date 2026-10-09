# Mint clone

A personal finance app inspired by Mint.com. Setup, commands and conventions are in [CLAUDE.md](CLAUDE.md).

## Signing in

Every page needs a signed-in user, and each user only sees their own accounts, transactions,
imports, categories, budgets and merchants. There's no sign-up page or email password reset:
create a user, or change a password, from a terminal in the app's directory.

```bash
bin/rails users:set_password EMAIL=you@example.com   # prompts for the password twice
```

A new user starts with the default categories. Changing a password signs that user out everywhere.

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
`bin/rails db:prepare` (migrates; keeps your QA data), builds Tailwind CSS, and starts Rails with
the Tailwind watcher in the background.

**Don't edit code in the QA Codespace.** Uncommitted changes and local commits on `staging` there
are discarded on every start. Untracked files (`log/`, `tmp/`, `storage/`, `.env*`) and the database are kept.

### If the Codespace is already running

```bash
bin/qa-refresh
```

### One-time reset for user accounts

Data from before user accounts has no owner, so the first startup with them stops at a migration
that says to reset the database (see `log/codespace.log`). This deletes all QA data. In the
Codespace terminal:

```bash
pkill -f puma                                        # stop Rails if it's running
bin/rails db:reset
bin/rails users:set_password EMAIL=you@example.com
bin/qa-refresh
```

### Debugging

- Startup log: `log/codespace.log` (Rails request log: `log/development.log`)
- Is Rails up? `curl -sI localhost:3000/up` should print `HTTP/1.1 200 OK` (every other page
  redirects to sign in)
- Restart Rails: `bin/qa-refresh`
- Your URL (bookmark this once): `echo https://$CODESPACE_NAME-3000.$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN`,
  also printed at the end of `log/codespace.log`. The pattern is
  `https://<codespace-name>-3000.app.github.dev`. It belongs to the Codespace, so it stays the same
  as long as you keep this Codespace.

### If the app URL shows 502

First check `curl -sI localhost:3000/up` in the Codespace. If it returns `HTTP/1.1 200 OK` but the
browser still shows 502, Rails is running and the Codespaces port-forwarding tunnel may be stale.
In VS Code, open the **Ports** tab, right-click port `3000`, choose **Stop Forwarding Port**, then
click **Forward a Port**, enter `3000`, and choose **Open in Browser** for the newly forwarded port.
Keep the port visibility **Private**. If Rails is not responding locally, use `bin/qa-refresh`
instead.

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
