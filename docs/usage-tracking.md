# Usage Tracking

Agent Pulse shows your current **5-hour** and **weekly** usage for Claude and
Codex next to each agent's live work status. It reuses the logins you already
have on your Mac — there is nothing extra to sign in to.

## What you see

### Menu bar

Each agent is a split pill, for example `Cl 34` and `Cx 40`:

- **Left half** — live work status from hook events: brand color when idle,
  green while working, purple when just finished (fades back after a moment),
  red on failure, amber while waiting on a prompt, gray when a session goes
  stale.
- **Right half** — the agent's brand color with the **5-hour** usage percentage
  (`--` when usage is unavailable).

### Dropdown

Click either pill to open the panel. Each agent row adds:

- a **5h** bar and a **Week** bar, each with `42% · resets 4:30 PM` /
  `67% · resets Tue`,
- or, when usage can't be read, the reason ("Not logged in", "Keychain access
  denied", "CLI not found", …),
- a **last-updated** time in the header and a **refresh** button that
  re-checks all logins and refetches both agents.

Usage refreshes automatically every 5 minutes by default (configurable). Work
status is always live from hooks and is independent of the usage poll.

## How authentication works

### Claude

Agent Pulse finds your Claude credentials by checking these locations in order:

1. `~/.claude/.credentials.json`
2. macOS Keychain service `Claude Code-credentials`
3. the `CLAUDE_CODE_OAUTH_TOKEN` environment variable
4. **Claude Desktop**: the encrypted OAuth token cache in
   `~/Library/Application Support/Claude/config.json`, decrypted using the
   macOS Keychain service `Claude Safe Storage`

It then calls:

- Usage: `https://api.anthropic.com/api/oauth/usage`
- Token refresh (when the access token is near expiry):
  `https://platform.claude.com/v1/oauth/token`

**Claude Desktop is read-only.** When a token comes from Claude Desktop, Agent
Pulse never writes back to Desktop's `config.json`; a refreshed token is kept in
memory only. Refreshed tokens from the credentials file or Keychain are written
back to that same source. If Claude Desktop is closed and its token has expired,
usage may go stale until Desktop runs again or you log in through the CLI.

### Codex

Agent Pulse reads Codex usage by launching `codex app-server` with your existing
Codex CLI login (from your home directory, so there are no workspace-trust
prompts). It does not handle Codex credentials itself — if `codex` works in your
terminal, it works here.

## Keychain prompts

The first time Agent Pulse reads Claude credentials, macOS may ask permission to
access the `Claude Code-credentials` and/or `Claude Safe Storage` Keychain
items. This is expected — the app is reading Claude's own local auth state.
Approve it (choose "Always Allow" to avoid repeat prompts).

Because the app bundle is **ad-hoc signed**, its signature changes every time you
rebuild it with `scripts/build-app-bundle`. macOS treats a new signature as a
different app, so it will prompt again after a rebuild. A stable signing identity
(self-signed or Developer ID) avoids the repeat prompts.

## Colors

Claude and Codex brand colors are customizable in the config window (with a
reset-to-default for each). Work-status colors (green/purple/red/amber/gray) are
fixed so their meaning stays consistent.

## Privacy

- **No telemetry** — nothing is tracked or phoned home.
- **No backend** — there is no proxy or server between you and the providers.
- **Local only** — credentials come from your existing CLI or Claude Desktop
  auth state.
- **Direct connections** — usage requests go from your Mac straight to the
  provider endpoints listed above.
- **Tokens stay on your machine** — they are never transmitted anywhere except
  to the provider's own endpoints.

This app depends on local auth state and provider APIs that can change. If you
use it in a security-sensitive environment, review the code first.

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| Claude shows "Not logged in" | Log in with `claude`, or sign into Claude Desktop, or set `CLAUDE_CODE_OAUTH_TOKEN` |
| Claude shows "Keychain access denied" | A Keychain prompt was dismissed — click the refresh button and approve it |
| Claude shows "Session expired" | Log in again with the Claude CLI or Desktop app |
| Codex shows "CLI not found" | Make sure `codex` is installed and on your `PATH` |
| Codex shows "Not logged in" | Run `codex` once in a terminal and complete login |
| Usage stuck on `--` | Click refresh; if it persists, relaunch so the app picks up your current shell environment |
| macOS keeps prompting for Keychain after each build | Expected with ad-hoc signing; use a stable signing identity to stop the repeats |
