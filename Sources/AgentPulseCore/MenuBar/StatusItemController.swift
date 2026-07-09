import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let runtime: AgentPulseRuntime
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let pillsView = MenuBarPillsView()
    private var configWindowController: NSWindowController?
    private var hotKey: GlobalHotKey?
    private var cancellables: Set<AnyCancellable> = []
    private var globalClickMonitor: Any?
    private var appResignObserver: NSObjectProtocol?

    init(runtime: AgentPulseRuntime) {
        self.runtime = runtime
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        configureStatusItem()
        configurePopover()
        configureHotKey()
        bindUpdates()
        updateStatusItem()
    }

    deinit {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = nil
        button.title = ""
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Agent Pulse"

        pillsView.brandColor = { [weak runtime] agent in
            runtime?.appearance.nsColor(for: agent) ?? agent.brandAccentNSColor
        }
        pillsView.frame = button.bounds
        pillsView.autoresizingMask = [.width, .height]
        button.addSubview(pillsView)
    }

    private func configurePopover() {
        // .semitransient dismisses on interaction with other windows but not on
        // the status-item click itself, so the toggle below stays in control.
        popover.behavior = .semitransient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: makeDropdownView())
    }

    private func makeDropdownView() -> AgentStatusPanel {
        AgentStatusPanel(
            runtime: runtime,
            store: runtime.store,
            usageStore: runtime.usageStore,
            appearance: runtime.appearance,
            openConfig: { [weak self] in
                self?.showConfigWindow()
            }
        )
    }

    private func configureHotKey() {
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.togglePopover()
        }
    }

    private func bindUpdates() {
        for publisher in [
            runtime.objectWillChange,
            runtime.store.objectWillChange,
            runtime.usageStore.objectWillChange,
            runtime.appearance.objectWillChange,
        ] {
            publisher
                .sink { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.updateStatusItem()
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let snapshots = runtime.store.orderedSnapshots
        pillsView.pills = snapshots.map { snapshot in
            MenuBarPillBuilder.pill(
                agent: snapshot.agent,
                effectiveState: runtime.store.effectiveState(for: snapshot),
                usedPercentage: runtime.usageStore.snapshot(for: snapshot.agent).fiveHour.usedPercentage
            )
        }
        statusItem.length = pillsView.fittingWidth()
        // The pill model is unchanged when only a brand color changes, so force
        // a repaint to pick up a new custom color.
        pillsView.needsDisplay = true

        button.toolTip = snapshots
            .map { snapshot in
                let state = runtime.store.effectiveState(for: snapshot)
                let usage = runtime.usageStore.snapshot(for: snapshot.agent)
                let fiveHour = MenuBarPillBuilder.usageText(for: usage.fiveHour.usedPercentage)
                let weekly = MenuBarPillBuilder.usageText(for: usage.weekly.usedPercentage)
                return "\(snapshot.agent.displayName): \(state.displayName) · 5h \(fiveHour)% · week \(weekly)%"
            }
            .joined(separator: "\n")
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        togglePopover()
    }

    private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            closePopover()
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startDismissMonitoring()
    }

    private func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
        stopDismissMonitoring()
    }

    /// A global monitor fires for clicks in *other* apps (not our own status
    /// item or popover), so clicking away closes the popover while the status
    /// item click keeps toggling it.
    private func startDismissMonitoring() {
        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    self?.closePopover()
                }
            }
        }

        if appResignObserver == nil {
            appResignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.closePopover()
                }
            }
        }
    }

    private func stopDismissMonitoring() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }

        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
            self.appResignObserver = nil
        }
    }

    private func showConfigWindow() {
        closePopover()

        if let window = configWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: AgentPulseConfigView(runtime: runtime, appearance: runtime.appearance)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.title = "Agent Pulse Config"

        let controller = NSWindowController(window: window)
        configWindowController = controller
        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
