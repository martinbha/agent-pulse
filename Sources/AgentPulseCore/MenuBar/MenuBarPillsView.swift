import AppKit

/// Draws the menu bar's split pills. Each pill is a capsule divided down the
/// middle: the left half is filled with the work-status color (brand color when
/// idle) and shows the agent label; the right half is the brand color and shows
/// the 5-hour usage number. The view sizes itself to its content.
final class MenuBarPillsView: NSView {
    var pills: [MenuBarPill] = [] {
        didSet {
            guard pills != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// Resolves the brand color for an agent (indirection so custom colors can
    /// be injected later without changing the drawing code).
    var brandColor: (AgentKind) -> NSColor = { $0.brandAccentNSColor }

    private let pillHeight: CGFloat = 15
    private let horizontalPadding: CGFloat = 5.5
    private let pillSpacing: CGFloat = 5
    private let sideMargin: CGFloat = 2

    private static var font: NSFont { AgentPulseFont.nsFont(size: 11, weight: .semibold) }

    override var isFlipped: Bool { false }

    // Let clicks fall through to the enclosing status item button.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: totalWidth(), height: NSView.noIntrinsicMetric)
    }

    func fittingWidth() -> CGFloat {
        totalWidth()
    }

    private func halfWidth(for pill: MenuBarPill) -> CGFloat {
        let labelWidth = measure(pill.label)
        let usageWidth = measure(pill.usageText)
        return max(labelWidth, usageWidth) + horizontalPadding * 2
    }

    private func pillWidth(for pill: MenuBarPill) -> CGFloat {
        halfWidth(for: pill) * 2
    }

    private func totalWidth() -> CGFloat {
        guard !pills.isEmpty else { return 0 }
        let pillsWidth = pills.reduce(0) { $0 + pillWidth(for: $1) }
        let spacing = pillSpacing * CGFloat(pills.count - 1)
        return pillsWidth + spacing + sideMargin * 2
    }

    private func measure(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: Self.font]).width.rounded(.up)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        var x = sideMargin
        let y = ((bounds.height - pillHeight) / 2).rounded()

        for pill in pills {
            let width = pillWidth(for: pill)
            let rect = NSRect(x: x, y: y, width: width, height: pillHeight)
            draw(pill, in: rect)
            x += width + pillSpacing
        }
    }

    private func draw(_ pill: MenuBarPill, in rect: NSRect) {
        let brand = brandColor(pill.agent)
        let leftColor = AgentPulseColors.pillStatusFill(for: pill.state, brand: brand)
        let radius = rect.height / 2

        let capsule = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let midX = rect.midX

        NSGraphicsContext.saveGraphicsState()
        capsule.addClip()
        leftColor.setFill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: midX - rect.minX, height: rect.height)).fill()
        brand.setFill()
        NSBezierPath(rect: NSRect(x: midX, y: rect.minY, width: rect.maxX - midX, height: rect.height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        let leftRect = NSRect(x: rect.minX, y: rect.minY, width: midX - rect.minX, height: rect.height)
        let rightRect = NSRect(x: midX, y: rect.minY, width: rect.maxX - midX, height: rect.height)
        drawText(pill.label, in: leftRect)
        drawText(pill.usageText, in: rightRect)
    }

    private func drawText(_ text: String, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]

        let textHeight = (text as NSString).size(withAttributes: attributes).height
        let textRect = NSRect(
            x: rect.minX,
            y: rect.minY + (rect.height - textHeight) / 2,
            width: rect.width,
            height: textHeight
        )
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }
}
