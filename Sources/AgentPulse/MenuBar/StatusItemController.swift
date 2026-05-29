import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let runtime: AgentPulseRuntime
    private let statusItem: NSStatusItem
    private let panel: AgentPulsePanel
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

        button.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Agent Pulse")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Agent Pulse"
    }

    private func configurePanel() {
        panel.setContentSize(panelSize)
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
        runtime.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)

        runtime.store.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let title = NSMutableAttributedString()
        for snapshot in runtime.store.orderedSnapshots {
            let state = runtime.store.effectiveState(for: snapshot)
            title.append(dotAttachment(outerColor: nsColor(for: state), innerColor: snapshot.agent.brandAccentNSColor))
            title.append(NSAttributedString(string: " "))
        }

        button.attributedTitle = title
        button.toolTip = runtime.store.orderedSnapshots
            .map { snapshot in
                let state = runtime.store.effectiveState(for: snapshot)
                return "\(snapshot.agent.displayName): \(state.displayName)"
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

    private func dotAttachment(outerColor: NSColor, innerColor: NSColor) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = dotImage(outerColor: outerColor, innerColor: innerColor)
        attachment.bounds = NSRect(x: 0, y: -3, width: 16, height: 16)
        return NSAttributedString(attachment: attachment)
    }

    private func dotImage(outerColor: NSColor, innerColor: NSColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()

        let outerRect = NSRect(x: 1, y: 1, width: 14, height: 14)
        outerColor.setFill()
        NSBezierPath(ovalIn: outerRect).fill()

        NSColor.black.withAlphaComponent(0.12).setStroke()
        let outerStroke = NSBezierPath(ovalIn: outerRect.insetBy(dx: 0.25, dy: 0.25))
        outerStroke.lineWidth = 0.5
        outerStroke.stroke()

        let innerRect = NSRect(x: 5, y: 5, width: 6, height: 6)
        innerColor.setFill()
        NSBezierPath(ovalIn: innerRect).fill()

        NSColor.black.withAlphaComponent(0.18).setStroke()
        let innerStroke = NSBezierPath(ovalIn: innerRect.insetBy(dx: 0.25, dy: 0.25))
        innerStroke.lineWidth = 0.5
        innerStroke.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
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

    private func nsColor(for state: AgentState) -> NSColor {
        switch state {
        case .idle:
            return .secondaryLabelColor
        case .working:
            return .systemBlue
        case .waiting:
            return .systemYellow
        case .done:
            return .systemGreen
        case .failed:
            return .systemRed
        case .stale:
            return .systemOrange
        case .unknown:
            return .tertiaryLabelColor
        }
    }
}

final class AgentPulsePanel: NSPanel {
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
}
