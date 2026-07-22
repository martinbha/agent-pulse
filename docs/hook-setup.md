# Hook Setup

Agent Pulse receives events from Claude Code and Codex through a small native bridge.

For normal installation, open **Setup** from the Agent Pulse menu and select
**Set Up** on each tool you want to connect. Agent Pulse installs the bridge,
backs up an existing configuration before changing it, preserves unrelated
settings, and refreshes the displayed health after each operation. No manual
configuration editing is required.

After setup, select **Test** on an integration card to run the installed bridge
with a uniquely correlated event. The app verifies delivery through its
authenticated local state endpoint, reports the exact failing stage when the
test does not pass, and refreshes setup health afterward. Self-test events do
not change the displayed agent state or produce normal event notifications.

The details below are a development and troubleshooting reference for the
files managed by Setup.

The app writes local connection details to:

```text
~/.agent-pulse/config.json
```

The bridge reads that file, normalizes hook payloads, and sends events to:

```text
http://127.0.0.1:37462/v1/events
```

## Manual bridge installation reference

From this repository:

```bash
scripts/build-app-bundle
install -d -m 700 "$HOME/.agent-pulse/bin"
install -m 755 "dist/Agent Pulse.app/Contents/Helpers/agent-pulse-hook" \
  "$HOME/.agent-pulse/bin/agent-pulse-hook"
```

Start Agent Pulse once before testing hooks so `~/.agent-pulse/config.json` exists.

## Claude Code

Add hooks to `~/.claude/settings.json`.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.agent-pulse/bin/agent-pulse-hook claude",
            "timeout": 2
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.agent-pulse/bin/agent-pulse-hook claude",
            "timeout": 2
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.agent-pulse/bin/agent-pulse-hook claude",
            "timeout": 2
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.agent-pulse/bin/agent-pulse-hook claude",
            "timeout": 2
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.agent-pulse/bin/agent-pulse-hook claude",
            "timeout": 2
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.agent-pulse/bin/agent-pulse-hook claude",
            "timeout": 2
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.agent-pulse/bin/agent-pulse-hook claude",
            "timeout": 2
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.agent-pulse/bin/agent-pulse-hook claude",
            "timeout": 2
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.agent-pulse/bin/agent-pulse-hook claude",
            "timeout": 2
          }
        ]
      }
    ]
  }
}
```

## Codex

Add hooks to `~/.codex/config.toml`.

```toml
# BEGIN agent-pulse
[[hooks.SessionStart]]
matcher = "startup|resume|clear|compact"
[[hooks.SessionStart.hooks]]
type = "command"
command = "$HOME/.agent-pulse/bin/agent-pulse-hook codex"
timeout = 2
statusMessage = "Updating Agent Pulse"

[[hooks.UserPromptSubmit]]
[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "$HOME/.agent-pulse/bin/agent-pulse-hook codex"
timeout = 2
statusMessage = "Updating Agent Pulse"

[[hooks.PreToolUse]]
matcher = "*"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "$HOME/.agent-pulse/bin/agent-pulse-hook codex"
timeout = 2
statusMessage = "Updating Agent Pulse"

[[hooks.PostToolUse]]
matcher = "*"
[[hooks.PostToolUse.hooks]]
type = "command"
command = "$HOME/.agent-pulse/bin/agent-pulse-hook codex"
timeout = 2
statusMessage = "Updating Agent Pulse"

[[hooks.PermissionRequest]]
matcher = "*"
[[hooks.PermissionRequest.hooks]]
type = "command"
command = "$HOME/.agent-pulse/bin/agent-pulse-hook codex"
timeout = 2
statusMessage = "Updating Agent Pulse"

[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = "$HOME/.agent-pulse/bin/agent-pulse-hook codex"
timeout = 2
statusMessage = "Updating Agent Pulse"
# END agent-pulse
```

The TOML integration supports only the six event tables shown above. Agent
Pulse owns the marker-delimited block and leaves all other TOML content intact.

## Delivery diagnostics

The **Test** button in Setup or Settings is the preferred delivery check. For a
terminal-based diagnostic, keep Agent Pulse running and execute:

```bash
"$HOME/.agent-pulse/bin/agent-pulse-hook" --doctor
```

Pass one integration name to limit the correlated delivery test:

```bash
"$HOME/.agent-pulse/bin/agent-pulse-hook" --doctor claude
"$HOME/.agent-pulse/bin/agent-pulse-hook" --doctor codex
```

The command checks bridge configuration, local connectivity and authorization,
then verifies that each requested correlated event appears in local state. It
prints a failure stage and recovery step without displaying the bearer token.
