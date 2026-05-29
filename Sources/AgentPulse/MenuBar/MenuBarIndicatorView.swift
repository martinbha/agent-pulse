import SwiftUI

struct MenuBarIndicatorView: View {
    @ObservedObject var store: AgentStatusStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(store.orderedSnapshots) { snapshot in
                let state = store.effectiveState(for: snapshot)
                StatusDot(state: state, size: 8)
                    .help("\(snapshot.agent.displayName): \(state.displayName)")
            }
        }
        .padding(.horizontal, 2)
    }
}

