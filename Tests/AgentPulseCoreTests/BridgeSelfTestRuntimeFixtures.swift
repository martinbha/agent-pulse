import Foundation
import AgentPulseBridgeSupport

@testable import AgentPulseCore

enum BridgeSelfTestRuntimeFixtures {
    struct StateSnapshot {
        var hasNoAgents: Bool
        var identifier: String?
    }

    static func receipt() -> BridgeSelfTestReceipt? {
        BridgeSelfTestEventReceipt.make(
            from: AgentEvent(
                agent: .codex,
                state: .working,
                event: BridgeSelfTestProtocol.event,
                sessionID: BridgeSelfTestProtocol.sessionID(for: "correlation-1"),
                cwd: "/tmp/project",
                project: "project",
                timestamp: Date(timeIntervalSince1970: 1_800_000_000),
                source: BridgeSelfTestProtocol.source
            )
        )
    }

    static func normalEventCreatesReceipt() -> Bool {
        BridgeSelfTestEventReceipt.make(
            from: AgentEvent(
                agent: .claude,
                state: .done,
                event: "Stop",
                sessionID: "normal-session",
                cwd: nil,
                project: nil,
                timestamp: Date(),
                source: "hook"
            )
        ) != nil
    }

    @MainActor
    static func encodedState(_ receipt: BridgeSelfTestReceipt) throws -> StateSnapshot {
        let response = ServerStateResponse(store: nil, selfTest: receipt)
        let data = try AgentPulseJSON.encoder.encode(response)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let agents = object?["agents"] as? [Any]
        let selfTest = object?["self_test"] as? [String: Any]
        return StateSnapshot(
            hasNoAgents: agents?.isEmpty == true,
            identifier: selfTest?["identifier"] as? String
        )
    }
}
