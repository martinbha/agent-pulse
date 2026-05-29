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

@MainActor
final class AgentPulseAppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: AgentPulseRuntime?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = AgentPulseImages.appIcon() {
            NSApplication.shared.applicationIconImage = appIcon
        }

        let runtime = AgentPulseRuntime()
        self.runtime = runtime
        self.statusItemController = StatusItemController(runtime: runtime)
        NSLog("Agent Pulse started with endpoint \(runtime.endpoint)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("Agent Pulse stopped")
    }
}
