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
`bin/rails db:prepare` (migrates; keeps your QA data), builds Tailwind CSS, and starts Rails with
the Tailwind watcher in the background.

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

### If the app URL shows 502

First check `curl -sI localhost:3000` in the Codespace. If it returns `HTTP/1.1 200 OK` but the
browser still shows 502, Rails is running and the Codespaces port-forwarding tunnel may be stale.
In VS Code, open the **Ports** tab, right-click port `3000`, choose **Stop Forwarding Port**, then
click **Forward a Port**, enter `3000`, and choose **Open in Browser** for the newly forwarded port.
Keep the port visibility **Private**. If Rails is not responding locally, use `bin/qa-refresh`
instead.

Port 3000 is private: it opens only for you, signed in to GitHub in that browser. Secrets
come from Codespaces secrets (github.com → Settings → Codespaces), never from the repo.
