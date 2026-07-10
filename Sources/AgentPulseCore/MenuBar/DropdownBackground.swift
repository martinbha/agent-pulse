import AppKit
import SwiftUI

/// Shared appearance for the dropdown surfaces (popover + pinned overlay).
///
/// Both surfaces are: blur, then a dark tint at `tintAlpha`, then a vertical
/// highlight-to-shadow sheen. The pinned panel builds all three itself
/// (`DropdownBackground`); the popover reuses its own built-in blur material
/// and gets the tint painted onto its frame view's layer — the documented way
/// to recolor an NSPopover including its arrow, which is drawn by a private
/// frame view outside our content (see StatusItemController).
enum DropdownSurface {
    /// Dark tint layered over the blur; also the popover frame layer color.
    static let tintAlpha: CGFloat = 0.8

    static var tintColor: NSColor {
        NSColor.black.withAlphaComponent(tintAlpha)
    }

    /// A vertical highlight-to-shadow wash over the tint gives the surface a
    /// subtle metallic sheen. Stops run top → bottom.
    static let sheenStops: [(alpha: CGFloat, isHighlight: Bool, location: CGFloat)] = [
        (0.10, true, 0.0),
        (0.03, true, 0.18),
        (0.0, true, 0.45),
        (0.14, false, 1.0),
    ]

    static var sheenGradient: LinearGradient {
        LinearGradient(
            stops: sheenStops.map { stop in
                Gradient.Stop(
                    color: (stop.isHighlight ? Color.white : Color.black).opacity(stop.alpha),
                    location: stop.location
                )
            },
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// AppKit sheen for the popover's frame view.
final class DropdownSheenView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CAGradientLayer()
        layer.colors = DropdownSurface.sheenStops.map { stop in
            (stop.isHighlight ? NSColor.white : NSColor.black)
                .withAlphaComponent(stop.alpha).cgColor
        }
        layer.locations = DropdownSurface.sheenStops.map { NSNumber(value: Double($0.location)) }
        // Layer coordinates have y = 1 at the top on this non-flipped view.
        layer.startPoint = CGPoint(x: 0.5, y: 1)
        layer.endPoint = CGPoint(x: 0.5, y: 0)
        return layer
    }
}

/// The pinned overlay's background: blur + tint + sheen.
struct DropdownBackground: View {
    var body: some View {
        ActiveVisualEffect()
            .overlay(Color.black.opacity(DropdownSurface.tintAlpha))
            .overlay(DropdownSurface.sheenGradient)
    }
}

private struct ActiveVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        // Pinned to active so the panel's blur matches the popover's instead
        // of lightening with window key state.
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
