import Foundation

@testable import AgentPulseCore

enum CodexHookTrustFixtures {
    static let bridgeURL = URL(fileURLWithPath: "/tmp/Agent Pulse/agent-pulse-hook")

    static func classify(
        statuses: [String],
        disabledIndexes: Set<Int> = [],
        includeUnrelatedHook: Bool = false
    ) -> HookTrustHealth {
        let events = Array(CodexHookTrustInspector.expectedEventNames).sorted()
        let command = "'/tmp/Agent Pulse/agent-pulse-hook' codex"
        var hooks: [[String: Any]] = statuses.enumerated().map { index, status in
            [
                "handlerType": "command",
                "command": command,
                "eventName": events[index],
                "enabled": !disabledIndexes.contains(index),
                "trustStatus": status,
            ]
        }
        if includeUnrelatedHook {
            hooks.append([
                "handlerType": "command",
                "command": "'/tmp/other-hook' codex",
                "eventName": "stop",
                "enabled": true,
                "trustStatus": "trusted",
            ])
        }

        return CodexHookTrustInspector.classify(
            payload: [
                "result": [
                    "data": [[
                        "hooks": hooks,
                        "errors": [],
                    ]],
                ],
            ],
            bridgeExecutableURL: bridgeURL,
            agentArgument: "codex"
        )
    }

    static func unavailableExecutableHealth() async -> HookTrustHealth {
        let inspector = CodexHookTrustInspector(
            executableURL: URL(fileURLWithPath: "/missing/command-client"),
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            bridgeExecutableURL: bridgeURL
        )
        return await inspector.inspect()
    }
}
