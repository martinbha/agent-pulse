import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let runtime: AgentPulseRuntime
    private let statusItem: NSStatusItem
    private let panel: AgentPulsePanel
    private let pillsView = MenuBarPillsView()
    private let panelSize = NSSize(width: 360, height: 260)
    private var configWindowController: NSWindowController?
    private var hotKey: GlobalHotKey?
    private var cancellables: Set<AnyCancellable> = []

    init(runtime: AgentPulseRuntime) {
        self.runtime = runtime
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panel = AgentPulsePanel()

        super.init()

        configureStatusItem()
        configurePanel()
        configureHotKey()
        bindUpdates()
        updateStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = nil
        button.title = ""
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Agent Pulse"

        pillsView.frame = button.bounds
        pillsView.autoresizingMask = [.width, .height]
        button.addSubview(pillsView)
    }

    private func configurePanel() {
        panel.setContentSize(panelSize)
        panel.didOrderOut = { [weak panel] in
            panel?.contentViewController = nil
        }
    }

    private func installPanelContent() {
        panel.contentViewController = NSHostingController(
            rootView: AgentStatusPanel(
                runtime: runtime,
                store: runtime.store,
                openConfig: { [weak self] in
                    self?.showConfigWindow()
                }
            )
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    @objc private func togglePopover(_ sender: Any?) {
        togglePanel()
    }

    private func togglePopover() {
        togglePanel()
    }

    private func togglePanel() {
        guard let button = statusItem.button else {
            return
        }

        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            installPanelContent()
            panel.setFrame(panelFrame(below: button), display: true)
            panel.orderFrontRegardless()
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func panelFrame(below button: NSStatusBarButton) -> NSRect {
        let screen = button.window?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let buttonFrame = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
        let margin: CGFloat = 8

        let x = clamp(
            buttonFrame.midX - panelSize.width / 2,
            min: visibleFrame.minX + margin,
            max: visibleFrame.maxX - panelSize.width - margin
        )

        let y = min(
            buttonFrame.minY - panelSize.height - margin,
            visibleFrame.maxY - panelSize.height - margin
        )

        return NSRect(
            x: x,
            y: max(y, visibleFrame.minY + margin),
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private func showConfigWindow() {
        if let window = configWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: AgentPulseConfigView(runtime: runtime))
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

final class AgentPulsePanel: NSPanel {
    var didOrderOut: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hasShadow = true
        hidesOnDeactivate = true
        isMovableByWindowBackground = false
        isOpaque = false
        isReleasedWhenClosed = false
        level = .floating
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        didOrderOut?()
    }
}
