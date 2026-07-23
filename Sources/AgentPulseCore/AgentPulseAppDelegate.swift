import AppKit

@MainActor
public final class AgentPulseAppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: AgentPulseRuntime?
    private var statusItemController: StatusItemController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = AgentPulseImages.appIcon() {
            NSApplication.shared.applicationIconImage = appIcon
        }

        let runtime = AgentPulseRuntime()
        self.runtime = runtime
        self.statusItemController = StatusItemController(runtime: runtime)
        NSLog("Agent Pulse started with endpoint \(runtime.endpoint)")
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        guard let runtime else {
            return
        }
        let setup = runtime.setup
        guard setup.snapshot != nil else {
            return
        }
        Task {
            await setup.refresh()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        NSLog("Agent Pulse stopped")
    }
}
