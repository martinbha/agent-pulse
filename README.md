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
- **Settings** — guided integration setup and health checks, notification and
  launch controls, customizable brand colors, usage refresh, shortcut
  configuration, and manual preview events.

Usage is fetched from your existing Claude and Codex logins with no separate
sign-in, and Claude Desktop auth state is read-only. See
[docs/usage-tracking.md](docs/usage-tracking.md) for the authentication sources,
expected Keychain prompts, and privacy details.

## Install from source

Agent Pulse currently supports macOS 14 and newer. Until Homebrew distribution
is available, building from source requires:

- Apple Command Line Tools with Swift 6 (`xcode-select --install`)
- Git

Clone and build the app:

```bash
git clone https://github.com/martinbha/agent-pulse.git
cd agent-pulse
scripts/build-app-bundle
mkdir -p "$HOME/Applications"
ditto "dist/Agent Pulse.app" "$HOME/Applications/Agent Pulse.app"
open "$HOME/Applications/Agent Pulse.app"
```

This source-built bundle is signed locally rather than notarized for download.
On first launch, Agent Pulse opens Settings automatically. Each detected tool has
its own status card; choose **Set Up** to install the local bridge and configure
that tool without editing files or running additional shell commands. The Codex
card separately reports configuration, hook approval, and the last live event.
Choose **Test Bridge** to verify only the authenticated local bridge path without
changing normal agent status or sending an event notification. A real task event
is still required to verify that the host loaded and executed the hooks. Settings
is always available from the menu-bar dropdown.

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

- [Work-status hooks](docs/hook-setup.md) — integration behavior, managed files,
  and a manual reference for development and troubleshooting.
- [Usage tracking](docs/usage-tracking.md) — how 5h and weekly usage are read,
  the authentication sources, Keychain prompts, and privacy.
