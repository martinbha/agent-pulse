import Testing

@testable import AgentPulseCore

@Suite struct NotificationPermissionServiceTests {
    @Test @MainActor func exposesMainAndPerIntegrationStatusAndRunsExplicitTest() async throws {
        let snapshot = try await NotificationPermissionServiceFixtures
            .statusesAndContextualTest()

        #expect(snapshot.main == .denied)
        #expect(snapshot.claude == .notDetermined)
        #expect(snapshot.codex == .authorized)
        #expect(snapshot.testedAgents == [.claude])
        #expect(snapshot.decodedAuthorized == .authorized)
        guard case .unavailable(let reason) = snapshot.decodedInvalid else {
            Issue.record("Expected invalid helper output to be unavailable")
            return
        }
        #expect(reason.contains("invalid authorization state"))
    }

    @Test func mapsEveryPlatformAuthorizationState() {
        #expect(NotificationPermissionService.health(from: .notDetermined) == .notDetermined)
        #expect(NotificationPermissionService.health(from: .denied) == .denied)
        #expect(NotificationPermissionService.health(from: .authorized) == .authorized)
        #expect(NotificationPermissionService.health(from: .provisional) == .provisional)
        #expect(NotificationPermissionService.health(from: .ephemeral) == .ephemeral)
        guard case .unavailable = NotificationPermissionService.health(from: .unknown) else {
            Issue.record("Expected unknown authorization to be unavailable")
            return
        }
    }
}
