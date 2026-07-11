import SwiftUI

/// Lets the user choose how often usage numbers are polled.
struct UsageRefreshSettings: View {
    @ObservedObject var usageStore: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Usage Refresh")
                .agentPulseFont(size: 15)

            HStack {
                Text("Polling interval")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Usage refresh interval", selection: refreshIntervalBinding) {
                    ForEach(UsageRefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .pickerStyle(.menu)
            }
            .agentPulseFont(size: 12)

            Text(helpText)
                .agentPulseFont(size: 11)
                .foregroundStyle(.secondary)
        }
    }

    private var refreshIntervalBinding: Binding<UsageRefreshInterval> {
        Binding(
            get: { usageStore.refreshInterval },
            set: { usageStore.setRefreshInterval($0) }
        )
    }

    private var helpText: String {
        switch usageStore.refreshInterval {
        case .manual:
            return "Automatic polling is paused until you refresh manually or choose another interval."
        default:
            return "Usage updates automatically every \(usageStore.refreshInterval.label.lowercased())."
        }
    }
}
