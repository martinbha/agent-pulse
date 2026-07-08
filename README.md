# Agent Pulse

Agent Pulse is a macOS menu bar utility that shows both the **live work status**
and the **current usage** of local AI coding agents such as Claude Code and
Codex.

It receives local hook events for work status, and reads your existing local
logins to fetch usage — combining them into a quiet ambient indicator.

> This project is unofficial and is not affiliated with, endorsed by, or
> maintained by Anthropic or OpenAI.

## What it shows

- **Menu bar** — one split pill per agent (e.g. `Cl 34`, `Cx 40`): the left half
  is the live work status (idle / working / done / failed / waiting / stale) and
  the right half is the **5-hour** usage percentage.
- **Dropdown** — click a pill for per-agent **5h** and **weekly** usage bars with
  reset times, the project and last event, a last-updated time, and a manual
  refresh button.
- **Config** — customizable Claude and Codex brand colors, and manual test
  events.

Usage is fetched from your existing Claude and Codex logins with no separate
sign-in, and Claude Desktop auth state is read-only. See
[docs/usage-tracking.md](docs/usage-tracking.md) for the authentication sources,
expected Keychain prompts, and privacy details.

## Development

Build the executable:

```bash
swift build
```

Run the app:

```bash
swift run agent-pulse
```

Run the tests (use the wrapper — it adds the framework search paths that
Command Line Tools-only installs need; with full Xcode, plain `swift test`
also works):

```bash
scripts/test
```

Build a launchable menu bar app bundle:

```bash
scripts/build-app-bundle
open "dist/Agent Pulse.app"
```

## Documentation

- [Work-status hooks](docs/hook-setup.md) — wire Claude Code and Codex hook
  events to Agent Pulse via the bridge script.
- [Usage tracking](docs/usage-tracking.md) — how 5h and weekly usage are read,
  the authentication sources, Keychain prompts, and privacy.
