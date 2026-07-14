import AppKit

enum AgentPulseImages {
    static func appIcon(size: NSSize? = nil) -> NSImage? {
        resourceImage(
            named: "agent-pulse-icon",
            extension: "svg",
            size: size,
            accessibilityDescription: "Agent Pulse"
        )
    }

    /// Rasterized agent logo used as the notification attachment thumbnail.
    @MainActor
    static func notificationLogoPNG(for agent: AgentKind) -> Data? {
        if let cached = notificationLogoCache[agent] {
            return cached
        }

        let name: String
        let description: String
        switch agent {
        case .claude:
            name = "claude-logo"
            description = "Claude"
        case .codex:
            name = "codex-logo"
            description = "Codex"
        }

        guard
            let image = resourceImage(
                named: name,
                extension: "svg",
                size: nil,
                accessibilityDescription: description
            ),
            let data = pngData(from: image, pixels: 256)
        else {
            return nil
        }

        notificationLogoCache[agent] = data
        return data
    }

    @MainActor
    private static var notificationLogoCache: [AgentKind: Data] = [:]

    private static func pngData(from image: NSImage, pixels: Int) -> Data? {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixels,
                pixelsHigh: pixels,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    private static func resourceImage(
        named name: String,
        extension fileExtension: String,
        size: NSSize?,
        accessibilityDescription: String? = nil
    ) -> NSImage? {
        let urls = [
            Bundle.main.url(forResource: name, withExtension: fileExtension),
            sourceResourceURL(named: name, extension: fileExtension)
        ].compactMap { $0 }

        for url in urls {
            guard let image = NSImage(contentsOf: url) else {
                continue
            }

            if let size {
                image.size = size
            }
            image.accessibilityDescription = accessibilityDescription
            return image
        }

        return nil
    }

    private static func sourceResourceURL(named name: String, extension fileExtension: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("\(name).\(fileExtension)")
    }
}
