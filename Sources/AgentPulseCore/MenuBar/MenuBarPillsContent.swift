import SwiftUI

/// The menu bar pills, rendered as a SwiftUI view (drawn to an image by the
/// status item). Each pill is a capsule split into a label section (work-status
/// color) and a usage section (brand color). Section widths are uniform across
/// pills, so every pill is the same size and the labels line up consistently.
struct MenuBarPillsContent: View {
    let pills: [MenuBarPill]
    var brandColor: (AgentKind) -> Color
    let labelSectionWidth: CGFloat
    let usageSectionWidth: CGFloat

    static let fontSize: CGFloat = 11
    private let pillHeight: CGFloat = 18
    private let pillSpacing: CGFloat = 6

    var body: some View {
        HStack(spacing: pillSpacing) {
            ForEach(pills) { pill in
                pillView(pill)
            }
        }
        .fixedSize()
    }

    private func pillView(_ pill: MenuBarPill) -> some View {
        HStack(spacing: 0) {
            section(pill.label, width: labelSectionWidth)
                .background(AgentPulseColors.pillStatusFill(for: pill.state, brand: brandColor(pill.agent)))
            section(pill.usageText, width: usageSectionWidth)
                .background(brandColor(pill.agent))
        }
        .clipShape(Capsule(style: .continuous))
    }

    private func section(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .agentPulseFont(size: Self.fontSize)
            .monospacedDigit()
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.22), radius: 0.5, y: 0.5)
            .frame(width: width, height: pillHeight)
    }
}

/// Computes the uniform pill section widths (shared by the renderer and tests).
enum MenuBarPillLayout {
    static let horizontalPadding: CGFloat = 7

    static func sectionWidths(
        pills: [MenuBarPill],
        measure: (String) -> CGFloat
    ) -> (label: CGFloat, usage: CGFloat) {
        let label = (pills.map { measure($0.label) }.max() ?? 0) + horizontalPadding * 2
        let usage = (pills.map { measure($0.usageText) }.max() ?? 0) + horizontalPadding * 2
        return (label.rounded(.up), usage.rounded(.up))
    }
}
