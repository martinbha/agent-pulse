import SwiftUI

@main
struct AgentPulseApp: App {
    @StateObject private var runtime = AgentPulseRuntime()

    var body: some Scene {
        MenuBarExtra {
            AgentStatusPanel(runtime: runtime, store: runtime.store)
        } label: {
            MenuBarIndicatorView(store: runtime.store)
        }
        .menuBarExtraStyle(.window)
    }
}
