import AppKit
import SwiftUI

/// The one opaque background shared by the menu-bar popover and pinned overlay.
///
/// The surface deliberately does not use a visual-effect material: materials
/// sample their host window and change their appearance between presentation
/// paths and activation states.
enum DropdownSurface {
    static let backgroundColor = NSColor(
        srgbRed: 21 / 255,
        green: 21 / 255,
        blue: 21 / 255,
        alpha: 1
    )

    static let borderColor = NSColor(
        srgbRed: 78 / 255,
        green: 78 / 255,
        blue: 78 / 255,
        alpha: 1
    )
}

/// An opaque SwiftUI surface for the pinned overlay and popover content.
struct DropdownBackground: View {
    var body: some View {
        Color(nsColor: DropdownSurface.backgroundColor)
    }
}

/// Custom menu-bar popover chrome. Drawing the arrow ourselves keeps it on the
/// same opaque surface as the panel body instead of using AppKit's separately
/// rendered popover arrow.
struct DropdownPopoverSurface<Content: View>: View {
    let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: DropdownPopoverShape.arrowHeight)
            content
        }
        .background {
            DropdownPopoverShape()
                .fill(Color(nsColor: DropdownSurface.backgroundColor))
        }
        .clipShape(DropdownPopoverShape())
        .overlay {
            DropdownPopoverShape()
                .stroke(Color(nsColor: DropdownSurface.borderColor), lineWidth: 1)
        }
    }
}

private struct DropdownPopoverShape: Shape {
    static let arrowHeight: CGFloat = 12
    private let cornerRadius: CGFloat = 16
    private let arrowWidth: CGFloat = 30
    private let arrowTipRadius: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let arrowHeight = min(Self.arrowHeight, rect.height / 2)
        let top = rect.minY + arrowHeight
        let radius = min(cornerRadius, rect.width / 2, (rect.height - arrowHeight) / 2)
        let arrowWidth = min(self.arrowWidth, rect.width - radius * 2)
        let arrowCenter = rect.midX
        let arrowLeft = arrowCenter - arrowWidth / 2
        let arrowRight = arrowCenter + arrowWidth / 2
        let tipRadius = min(arrowTipRadius, arrowWidth / 4)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: top))
        path.addLine(to: CGPoint(x: arrowLeft, y: top))
        path.addLine(to: CGPoint(x: arrowCenter - tipRadius, y: rect.minY + tipRadius))
        path.addQuadCurve(
            to: CGPoint(x: arrowCenter + tipRadius, y: rect.minY + tipRadius),
            control: CGPoint(x: arrowCenter, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: arrowRight, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: top + radius),
            control: CGPoint(x: rect.maxX, y: top)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: top + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: top),
            control: CGPoint(x: rect.minX, y: top)
        )
        path.closeSubpath()
        return path
    }
}
