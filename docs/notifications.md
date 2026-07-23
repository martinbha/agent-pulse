# Notifications

Agent Pulse posts a banner when an agent starts working and when it finishes.

## Per-agent sender identity

macOS draws the posting app's bundle icon on every banner and offers no API to
vary it per notification. To show the agent's own logo instead of the Agent
Pulse icon, the bundle nests one tiny notifier app per agent:

```text
Agent Pulse.app/Contents/Helpers/
  Agent Pulse Claude.app   (bundle icon: Claude logo)
  Agent Pulse Codex.app    (bundle icon: Codex logo)
```

Both wrap the same `agent-pulse-notifier` executable. The main app hands the
notification to the right helper via argv (see `NotifierCommand`); the helper
posts it under its own identity, so the banner's sender icon is the agent
logo. Because the logo is the sender icon rather than an attachment
thumbnail, hovering the banner does not reflow anything.

Setup shows the authorization state for each helper. A helper asks for
notification permission only when its integration-specific test action is
used, and then appears as its own row in System Settings → Notifications.
Routine hook events never trigger a permission prompt. When the helpers are
missing (running the bare binary from `swift build` instead of the app bundle),
the main app falls back to posting directly under its own identity without
requesting permission implicitly.

## Transient banners

Notifications are meant to be glanced at, not collected: the posting helper
stays alive for ~9 seconds, removes its delivered notification right after
the banner has hidden, and exits. Anything a dead helper left behind is swept
on the next post. Nothing accumulates in Notification Center.

The flip side: if a Focus mode suppresses the banner, the notification is
removed unseen — there is no way to distinguish "shown and hidden" from
"suppressed".

## Click to open the host app

The hook bridge reports `host_bundle_id` — the bundle id of the GUI app whose
process tree the agent runs in (`__CFBundleIdentifier`, set by macOS for
GUI-launched processes; absent under SSH). Clicking a banner relaunches the
helper that posted it, which activates that app and exits. Banners without a
host bundle id just dismiss.
