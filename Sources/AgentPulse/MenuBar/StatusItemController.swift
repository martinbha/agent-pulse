import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let runtime: AgentPulseRuntime
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables: Set<AnyCancellable> = []

    init(runtime: AgentPulseRuntime) {
        self.runtime = runtime
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()

        super.init()

        configureStatusItem()
        configurePopover()
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

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 360)
        popover.contentViewController = NSHostingController(
            rootView: AgentStatusPanel(runtime: runtime, store: runtime.store)
        )
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
            title.append(
                NSAttributedString(
                    string: "●",
                    attributes: [
                        .foregroundColor: nsColor(for: state),
                        .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
                    ]
                )
            )
            title.append(NSAttributedString(string: " "))
        }

        title.append(
            NSAttributedString(
                string: "Pulse",
                attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium)
                ]
            )
        )

        button.attributedTitle = title
        button.toolTip = runtime.store.orderedSnapshots
            .map { snapshot in
                let state = runtime.store.effectiveState(for: snapshot)
                return "\(snapshot.agent.displayName): \(state.displayName)"
            }
            .joined(separator: "\n")
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
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
