import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let runtime: AgentPulseRuntime
    private let statusItem: NSStatusItem
    private var statusItemView: StatusItemContentView?
    private var popoverPanel: AnchoredPopoverPanel?
    private var popoverHostingController: NSHostingController<AnyView>?
    private var configWindowController: NSWindowController?
    private var pinnedPanel: PinnedOverlayPanel?
    private var pinnedHostingController: NSHostingController<AnyView>?
    private var hotKey: GlobalHotKey?
    private var cancellables: Set<AnyCancellable> = []
    private var globalClickMonitor: Any?
    private var statusItemClickMonitor: Any?
    private var appResignObserver: NSObjectProtocol?
    private var popoverPresentationID: UUID?
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
        if let statusItemClickMonitor {
            NSEvent.removeMonitor(statusItemClickMonitor)
        }
        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
        }
    }

    private func configureStatusItem() {
        // The standard button participates in the system's menu-bar tracking,
        // which draws a selection hand-off flash when the pointer moves
        // between menu-bar apps; the button cell's highlight mask does not
        // govern that drawing. Use a custom status-item view so no native
        // button exists to be highlighted.
        let view = StatusItemContentView { [weak self] in
            self?.togglePopover()
        }
        view.toolTip = "Agent Pulse"
        statusItem.view = view
        statusItemView = view

        // AppKit routes clicks on the status window's padding — including the
        // band between the icon and the top screen edge — to its private
        // container view, never to a custom status-item view. The status
        // window belongs to this process, so a local monitor sees those
        // clicks before dispatch and can treat the whole window as the hit
        // target. Both halves of handled clicks are consumed so AppKit's
        // private container never sees a partial gesture. Cmd-modified clicks
        // pass through untouched to preserve drag-to-reorder handling.
        statusItemClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        ) { [weak self] event in
            guard let self,
                  let window = self.statusItemView?.window,
                  event.window === window,
                  !event.modifierFlags.contains(.command)
            else {
                return event
            }

            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                self.togglePopover()
            }
            return nil
        }
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
        guard let statusItemView else {
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
           renderPills(visualState, into: statusItemView) {
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
        if statusItemView.toolTip != toolTip {
            statusItemView.toolTip = toolTip
        }
    }

    @discardableResult
    private func renderPills(_ state: StatusItemVisualState, into statusItemView: StatusItemContentView) -> Bool {
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
        renderer.scale = statusItemView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else {
            return false
        }
        image.isTemplate = false
        if statusItem.length != image.size.width {
            statusItem.length = image.size.width
        }
        statusItemView.setImage(image, height: statusItem.statusBar?.thickness ?? NSStatusBar.system.thickness)
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

    private func statusItemFrameOnScreen() -> (frame: NSRect, screen: NSScreen?)? {
        guard let statusItemView, let statusItemWindow = statusItemView.window else {
            return nil
        }

        let frame = statusItemWindow.convertToScreen(
            statusItemView.convert(statusItemView.bounds, to: nil)
        )
        return (frame, statusItemWindow.screen)
    }

    private func positionPinnedPanel(_ panel: NSPanel) {
        guard let statusItemFrame = statusItemFrameOnScreen() else {
            panel.center()
            return
        }

        let size = panel.frame.size
        let visibleFrame = statusItemFrame.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 8

        let x = min(max(statusItemFrame.frame.midX - size.width / 2, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        let y = min(statusItemFrame.frame.minY - size.height - margin, visibleFrame.maxY - size.height - margin)
        panel.setFrameOrigin(NSPoint(x: x, y: max(y, visibleFrame.minY + margin)))
    }

    private func positionPopoverPanel(_ panel: NSPanel) {
        guard let statusItemFrame = statusItemFrameOnScreen() else {
            panel.center()
            return
        }

        let size = panel.frame.size
        let visibleFrame = statusItemFrame.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 8
        let x = min(max(statusItemFrame.frame.midX - size.width / 2, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        let y = min(statusItemFrame.frame.minY - size.height, visibleFrame.maxY - size.height)
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

/// Owns the complete status-item slot rather than overlaying the system button,
/// so no native button exists to draw menu-bar tracking highlights. Mouse
/// clicks are handled by the controller's local event monitor, which covers
/// the parts of the status window AppKit never routes to a custom view; this
/// view only renders the pills and answers accessibility.
@MainActor
private final class StatusItemContentView: NSView {
    private let onClick: () -> Void
    private var image: NSImage?

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        guard let image else {
            return NSSize(width: 1, height: NSStatusBar.system.thickness)
        }
        return NSSize(width: image.size.width, height: NSStatusBar.system.thickness)
    }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func accessibilityLabel() -> String? {
        "Agent Pulse"
    }

    func setImage(_ image: NSImage, height: CGFloat) {
        self.image = image
        setFrameSize(NSSize(width: image.size.width, height: height))
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let image else {
            return
        }

        let imageRect = NSRect(
            x: 0,
            y: floor((bounds.height - image.size.height) / 2),
            width: image.size.width,
            height: image.size.height
        )
        image.draw(in: imageRect)
    }

    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
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
