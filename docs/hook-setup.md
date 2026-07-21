# Hook Setup

Agent Pulse receives events from Claude Code and Codex through a small native bridge.

The app writes local connection details to:

```text
~/.agent-pulse/config.json
```

The bridge reads that file, normalizes hook payloads, and sends events to:

```text
http://127.0.0.1:37462/v1/events
```

## Install the native bridge

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

[[hooks.StopFailure]]
[[hooks.StopFailure.hooks]]
type = "command"
command = "$HOME/.agent-pulse/bin/agent-pulse-hook codex"
timeout = 2
statusMessage = "Updating Agent Pulse"

[[hooks.SubagentStop]]
[[hooks.SubagentStop.hooks]]
type = "command"
command = "$HOME/.agent-pulse/bin/agent-pulse-hook codex"
timeout = 2
statusMessage = "Updating Agent Pulse"
```

## Manual test

With Agent Pulse running, execute this from any project directory:

```bash
printf '{"hook_event_name":"UserPromptSubmit"}' \
  | "$HOME/.agent-pulse/bin/agent-pulse-hook" codex
```

Then query state:

```bash
TOKEN="$(plutil -extract token raw "$HOME/.agent-pulse/config.json")"
curl http://127.0.0.1:37462/v1/state -H "Authorization: Bearer $TOKEN"
```
