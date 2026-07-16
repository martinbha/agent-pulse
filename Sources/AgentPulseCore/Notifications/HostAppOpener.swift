import AppKit

public enum HostAppOpener {
    @MainActor
    @discardableResult
    public static func open(bundleID: String) async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSLog("Agent Pulse found no app for bundle id %@", bundleID)
            return false
        }

        do {
            try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch {
            NSLog("Agent Pulse could not open %@: %@", bundleID, error.localizedDescription)
            return false
        }
    }
}
