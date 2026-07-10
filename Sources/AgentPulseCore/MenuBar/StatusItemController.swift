import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let runtime: AgentPulseRuntime
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var popoverHostingController: NSHostingController<AnyView>?
    private weak var popoverBackgroundView: NSView?
    private var configWindowController: NSWindowController?
    private var pinnedPanel: PinnedOverlayPanel?
    private var pinnedHostingController: NSHostingController<AnyView>?
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

        button.title = ""
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Agent Pulse"
    }

    private func configurePopover() {
        // .semitransient dismisses on interaction with other windows but not on
        // the status-item click itself, so the toggle below stays in control.
        popover.behavior = .semitransient
        popover.animates = false

        let hostingController = NSHostingController(rootView: AnyView(makeDropdownView()))
        // We size the surfaces explicitly before showing them; automatic
        // preferred-size updates would resize the window *after* it has been
        // positioned, growing it upward past the menu bar.
        hostingController.sizingOptions = []
        popoverHostingController = hostingController
        popover.contentViewController = hostingController
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
        hotKey = GlobalHotKey { [weak self] in
            self?.togglePinnedPanel()
        }
        applyHotkeyShortcut()

        runtime.hotkeySettings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.applyHotkeyShortcut()
                }
            }
            .store(in: &cancellables)
    }

    private func applyHotkeyShortcut() {
        let shortcut = runtime.hotkeySettings.shortcut
        hotKey?.register(keyCode: UInt32(shortcut.keyCode), modifiers: shortcut.carbonModifiers)
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
        let pills = snapshots.map { snapshot in
            let usage = runtime.usageStore.snapshot(for: snapshot.agent)
            return MenuBarPillBuilder.pill(
                agent: snapshot.agent,
                effectiveState: runtime.store.effectiveState(for: snapshot),
                fiveHour: usage.fiveHour.usedPercentage,
                weekly: usage.weekly.usedPercentage
            )
        }
        renderPills(pills, into: button)

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

    private func renderPills(_ pills: [MenuBarPill], into button: NSStatusBarButton) {
        let measuringFont = AgentPulseFont.nsFont(size: MenuBarPillsContent.fontSize, weight: .semibold)
        let widths = MenuBarPillLayout.sectionWidths(pills: pills) { text in
            (text as NSString).size(withAttributes: [.font: measuringFont]).width
        }

        let content = MenuBarPillsContent(
            pills: pills,
            brandColor: { [weak runtime] agent in
                Color(nsColor: runtime?.appearance.nsColor(for: agent) ?? agent.brandAccentNSColor)
            },
            labelSectionWidth: widths.label,
            usageSectionWidth: widths.usage
        )

        let renderer = ImageRenderer(content: content)
        renderer.scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else {
            return
        }
        image.isTemplate = false
        button.image = image
        statusItem.length = image.size.width
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

        closePinnedPanel()
        popover.contentSize = dropdownContentSize(for: popoverHostingController)
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installPopoverBackgroundIfNeeded()
        startDismissMonitoring()
    }

    /// Recolors the popover by painting its frame view's layer — the
    /// documented way to restyle an NSPopover: the frame view draws the whole
    /// popover shape (arrow included), and a plain layer color doesn't vary
    /// with the window's focus state the way the built-in material does. The
    /// popover's own blur stays underneath, matching the pinned panel's
    /// blur + tint + sheen stack.
    private func installPopoverBackgroundIfNeeded() {
        guard let frameView = popover.contentViewController?.view.window?.contentView?.superview else {
            return
        }

        frameView.wantsLayer = true
        frameView.layer?.backgroundColor = DropdownSurface.tintColor.cgColor

        if popoverBackgroundView?.superview !== frameView {
            let sheen = DropdownSheenView(frame: frameView.bounds)
            sheen.autoresizingMask = [.width, .height]
            frameView.addSubview(sheen, positioned: .below, relativeTo: nil)
            popoverBackgroundView = sheen
        }
    }

    /// Measures the dropdown content at the moment of showing, clamped to the
    /// visible screen so the surface can never extend past the menu bar or off
    /// screen. Asks SwiftUI's layout directly (`sizeThatFits`) — with automatic
    /// sizing disabled, the hosting view's `fittingSize` has no constraints to
    /// answer from and undersizes.
    private func dropdownContentSize(for hostingController: NSHostingController<AnyView>?) -> NSSize {
        let width: CGFloat = 360
        guard let hostingController else {
            return NSSize(width: width, height: 400)
        }

        let fitted = hostingController.sizeThatFits(in: NSSize(width: width, height: 10_000))
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 20
        return NSSize(width: width, height: min(max(fitted.height, 200), maxHeight))
    }

    private func closePopover() {
        if popover.isShown {
            // close() is unconditional; performClose can be deferred while the
            // hotkey event is being handled, leaving both dropdowns visible.
            popover.close()
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

    // MARK: - Pinned overlay (hotkey)

    private func togglePinnedPanel() {
        if let pinnedPanel, pinnedPanel.isVisible {
            pinnedPanel.orderOut(nil)
            return
        }

        closePopover()

        let panel = pinnedPanel ?? makePinnedPanel()
        pinnedPanel = panel
        // Size to the current content before positioning: position math uses
        // the panel's frame, and a late auto-resize would grow the window
        // upward past the menu bar.
        panel.setContentSize(dropdownContentSize(for: pinnedHostingController))
        positionPinnedPanel(panel)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func closePinnedPanel() {
        pinnedPanel?.orderOut(nil)
    }

    private func makePinnedPanel() -> PinnedOverlayPanel {
        // The overlay stays above other apps (hidesOnDeactivate = false), so it
        // needs its own material background and rounded corners (unlike the
        // popover, which supplies its own chrome).
        let rootView = AnyView(
            makeDropdownView()
                .background(DropdownBackground())
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        let hostingController = NSHostingController(rootView: rootView)
        // Sizing is done explicitly in togglePinnedPanel before positioning;
        // automatic preferred-size updates would resize the already-placed
        // window upward past the menu bar.
        hostingController.sizingOptions = []
        pinnedHostingController = hostingController
        return PinnedOverlayPanel(contentViewController: hostingController)
    }

    private func positionPinnedPanel(_ panel: NSPanel) {
        guard let button = statusItem.button, let buttonWindow = button.window else {
            panel.center()
            return
        }

        let buttonOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 8

        let x = min(max(buttonOnScreen.midX - size.width / 2, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        let y = min(buttonOnScreen.minY - size.height - margin, visibleFrame.maxY - size.height - margin)
        panel.setFrameOrigin(NSPoint(x: x, y: max(y, visibleFrame.minY + margin)))
    }

    private func showConfigWindow() {
        closePopover()

        if let window = configWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: AgentPulseConfigView(
                runtime: runtime,
                appearance: runtime.appearance,
                hotkeySettings: runtime.hotkeySettings
            )
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

/// A borderless, draggable panel that floats above other apps and does not hide
/// when Agent Pulse is deactivated, so the hotkey overlay stays pinned.
final class PinnedOverlayPanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentViewController = contentViewController
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}
