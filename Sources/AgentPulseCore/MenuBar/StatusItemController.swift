import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let runtime: AgentPulseRuntime
    private let statusItem: NSStatusItem
    private var popoverPanel: AnchoredPopoverPanel?
    private var popoverHostingController: NSHostingController<AnyView>?
    private var configWindowController: NSWindowController?
    private var pinnedPanel: PinnedOverlayPanel?
    private var pinnedHostingController: NSHostingController<AnyView>?
    private var hotKey: GlobalHotKey?
    private var cancellables: Set<AnyCancellable> = []
    private var globalClickMonitor: Any?
    private var appResignObserver: NSObjectProtocol?
    private var popoverPresentationID: UUID?
    private var statusItemHitView: StatusItemHitView?
    private var isStatusItemUpdatePending = false
    private var renderedStatusItemState: StatusItemVisualState?

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
        button.toolTip = "Agent Pulse"

        // The dropdown is a custom panel, not an NSMenu. Letting AppKit's
        // status button track this click would briefly apply its native
        // selected state, then clear it when mouse tracking ends. An overlay
        // view keeps the status item visually neutral while still providing a
        // normal click target for the custom panel.
        let hitView = StatusItemHitView { [weak self] in
            self?.togglePopover()
        }
        hitView.frame = button.bounds
        hitView.autoresizingMask = [.width, .height]
        hitView.toolTip = button.toolTip
        button.addSubview(hitView)
        statusItemHitView = hitView
    }

    private func configurePopover() {
        let rootView = AnyView(DropdownPopoverSurface(content: makeDropdownView()))
        let hostingController = NSHostingController(rootView: rootView)
        // We size the surfaces explicitly before showing them; automatic
        // preferred-size updates would resize the window *after* it has been
        // positioned, growing it upward past the menu bar.
        hostingController.sizingOptions = []
        popoverHostingController = hostingController
        popoverPanel = AnchoredPopoverPanel(contentViewController: hostingController)
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
                    self?.scheduleStatusItemUpdate()
                }
                .store(in: &cancellables)
        }
    }

    private func scheduleStatusItemUpdate() {
        guard !isStatusItemUpdatePending else {
            return
        }

        isStatusItemUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.isStatusItemUpdatePending = false
            self.updateStatusItem()
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
        let visualState = StatusItemVisualState(
            pills: pills,
            brandColors: Dictionary(
                uniqueKeysWithValues: AgentKind.allCases.map { agent in
                    (agent, runtime.appearance.rgb(for: agent))
                }
            )
        )

        if visualState != renderedStatusItemState,
           renderPills(visualState, into: button) {
            renderedStatusItemState = visualState
        }

        let toolTip = snapshots
            .map { snapshot in
                let state = runtime.store.effectiveState(for: snapshot)
                let usage = runtime.usageStore.snapshot(for: snapshot.agent)
                let fiveHour = MenuBarPillBuilder.usageText(for: usage.fiveHour.usedPercentage)
                let weekly = MenuBarPillBuilder.usageText(for: usage.weekly.usedPercentage)
                return "\(snapshot.agent.displayName): \(state.displayName) · 5h \(fiveHour)% · week \(weekly)%"
            }
            .joined(separator: "\n")
        if button.toolTip != toolTip {
            button.toolTip = toolTip
            statusItemHitView?.toolTip = toolTip
        }
    }

    @discardableResult
    private func renderPills(_ state: StatusItemVisualState, into button: NSStatusBarButton) -> Bool {
        let measuringFont = AgentPulseFont.nsFont(size: MenuBarPillsContent.fontSize, weight: .semibold)
        let widths = MenuBarPillLayout.sectionWidths(pills: state.pills) { text in
            (text as NSString).size(withAttributes: [.font: measuringFont]).width
        }

        let content = MenuBarPillsContent(
            pills: state.pills,
            brandColor: { agent in
                Color(nsColor: state.brandColors[agent]?.nsColor ?? agent.brandAccentNSColor)
            },
            labelSectionWidth: widths.label,
            usageSectionWidth: widths.usage
        )

        let renderer = ImageRenderer(content: content)
        renderer.scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else {
            return false
        }
        image.isTemplate = false
        button.image = image
        if statusItem.length != image.size.width {
            statusItem.length = image.size.width
        }
        return true
    }

    private func togglePopover() {
        if let popoverPanel, popoverPanel.isVisible {
            closePopover()
            return
        }

        closePinnedPanel()
        let panel = popoverPanel ?? makePopoverPanel()
        popoverPanel = panel
        let presentationID = UUID()
        popoverPresentationID = presentationID
        panel.setContentSize(dropdownContentSize(for: popoverHostingController))
        positionPopoverPanel(panel)
        // This panel deliberately does not activate the app. The status item
        // is a neutral custom click surface, so opening the panel never needs
        // to manipulate NSStatusBarButton's native selected state.
        panel.makeKeyAndOrderFront(nil)
        startDismissMonitoring(for: presentationID)
    }

    private func makePopoverPanel() -> AnchoredPopoverPanel {
        let rootView = AnyView(DropdownPopoverSurface(content: makeDropdownView()))
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = []
        popoverHostingController = hostingController
        return AnchoredPopoverPanel(contentViewController: hostingController)
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

    private func closePopover(presentationID: UUID? = nil) {
        guard presentationID == nil || presentationID == popoverPresentationID else {
            return
        }

        popoverPanel?.orderOut(nil)
        popoverPresentationID = nil
        stopDismissMonitoring()
    }

    /// A global monitor closes the custom panel for clicks sent to other apps.
    /// The presentation ID makes a delayed monitor callback harmless after the
    /// user has reopened the panel.
    private func startDismissMonitoring(for presentationID: UUID) {
        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    self?.closePopover(presentationID: presentationID)
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
                    self?.closePopover(presentationID: presentationID)
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
        // needs rounded corners (unlike the popover, which supplies its own
        // chrome). Its content provides the shared opaque background.
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

    private func positionPopoverPanel(_ panel: NSPanel) {
        guard let button = statusItem.button, let buttonWindow = button.window else {
            panel.center()
            return
        }

        let buttonOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 8
        let x = min(max(buttonOnScreen.midX - size.width / 2, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        let y = min(buttonOnScreen.minY - size.height, visibleFrame.maxY - size.height)
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

private struct StatusItemVisualState: Equatable {
    let pills: [MenuBarPill]
    let brandColors: [AgentKind: RGBColor]
}

/// Receives menu-bar clicks without putting NSStatusBarButton into its native
/// pressed/selected tracking state. The button continues to render the image
/// beneath this transparent view.
@MainActor
private final class StatusItemHitView: NSView {
    private let onClick: () -> Void
    private var isTrackingClick = false

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        isTrackingClick = true
    }

    override func mouseUp(with event: NSEvent) {
        triggerClickIfNeeded(for: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        isTrackingClick = true
    }

    override func rightMouseUp(with event: NSEvent) {
        triggerClickIfNeeded(for: event)
    }

    private func triggerClickIfNeeded(for event: NSEvent) {
        defer { isTrackingClick = false }
        guard isTrackingClick else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else {
            return
        }
        onClick()
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

/// A custom, status-item-anchored panel that draws its own arrow so the entire
/// surface uses the same opaque background color.
final class AnchoredPopoverPanel: NSPanel {
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
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}
