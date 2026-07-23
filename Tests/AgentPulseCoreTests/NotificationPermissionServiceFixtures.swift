import Foundation

@testable import AgentPulseCore

struct NotificationPermissionServiceSnapshot {
    let main: NotificationAuthorizationHealth
    let claude: NotificationAuthorizationHealth
    let codex: NotificationAuthorizationHealth
    let testedAgents: [AgentKind]
    let decodedAuthorized: NotificationAuthorizationHealth
    let decodedInvalid: NotificationAuthorizationHealth
}

@MainActor
private final class NotificationPermissionServiceState {
    var testedAgents: [AgentKind] = []
}

enum NotificationPermissionServiceFixtures {
    @MainActor
    static func statusesAndContextualTest() async throws -> NotificationPermissionServiceSnapshot {
        let state = NotificationPermissionServiceState()
        let service = NotificationPermissionService(
            mainStatusProvider: { .denied },
            helperStatusProvider: { agent in
                agent == .claude ? .notDetermined : .authorized
            },
            testSender: { agent in
                state.testedAgents.append(agent)
            }
        )

        let main = await service.mainHealth()
        let claude = await service.helperHealth(for: .claude)
        let codex = await service.helperHealth(for: .codex)
        try await service.sendTest(for: .claude)

        return NotificationPermissionServiceSnapshot(
            main: main,
            claude: claude,
            codex: codex,
            testedAgents: state.testedAgents,
            decodedAuthorized: NotificationPermissionService.decodeHelperStatus(
                "authorized\n"
            ),
            decodedInvalid: NotificationPermissionService.decodeHelperStatus(
                "not-a-status"
            )
        )
    }
}
