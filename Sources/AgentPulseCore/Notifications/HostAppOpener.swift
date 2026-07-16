import AppKit

public enum HostAppOpener {
    @MainActor
    public static func open(bundleID: String) async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSLog("Agent Pulse found no app for bundle id %@", bundleID)
            return
        }

        do {
            try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            NSLog("Agent Pulse could not open %@: %@", bundleID, error.localizedDescription)
        }
    }
}
