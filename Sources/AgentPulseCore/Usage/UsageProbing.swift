import Foundation

protocol UsageProbing: Sendable {
    func fetch(trigger: RefreshTrigger) async -> AgentUsageSnapshot
}

extension ClaudeUsageProbe: UsageProbing {}
extension CodexUsageProbe: UsageProbing {}
