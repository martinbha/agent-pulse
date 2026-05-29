# Agent Pulse

Agent Pulse is a macOS menu bar utility for showing the current status of local AI coding agents such as Claude Code and Codex.

The app receives local hook events, normalizes them into a small status model, and renders the result as a quiet ambient indicator.

## Development

Build the executable:

```bash
swift build
```

Run the app:

```bash
swift run agent-pulse
```

The first implementation targets a Swift Package executable so the core app can be built with Command Line Tools. A full `.app` bundle and WidgetKit extension can be added after the core event loop is stable.

