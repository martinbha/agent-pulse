import AgentPulseCore
import AppKit

@main
enum AgentPulseApp {
    @MainActor private static var appDelegate: AgentPulseAppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AgentPulseAppDelegate()
        appDelegate = delegate
        app.delegate = delegate

        app.run()
    }
}
