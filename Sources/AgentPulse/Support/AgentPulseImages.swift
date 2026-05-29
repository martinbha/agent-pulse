import AppKit

enum AgentPulseImages {
    static func menuBarIcon() -> NSImage? {
        guard let image = resourceImage(
            named: "agent-pulse-menubar",
            extension: "svg",
            size: NSSize(width: 22, height: 12)
        ) else {
            let fallback = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Agent Pulse")
            fallback?.isTemplate = true
            return fallback
        }

        image.isTemplate = true
        image.accessibilityDescription = "Agent Pulse"
        return image
    }

    static func appIcon(size: NSSize? = nil) -> NSImage? {
        resourceImage(
            named: "agent-pulse-icon",
            extension: "svg",
            size: size,
            accessibilityDescription: "Agent Pulse"
        )
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
