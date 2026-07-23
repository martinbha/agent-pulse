import Testing

@testable import AgentPulseCore

@Suite struct LaunchAtLoginServiceTests {
    @Test @MainActor func enablingAndDisablingConfirmTheResultingSystemState() {
        let enabled = LaunchAtLoginServiceFixtures.enablingPackagedApplication()
        let disabled = LaunchAtLoginServiceFixtures.disablingPackagedApplication()

        #expect(enabled.health == .enabled)
        #expect(enabled.registerCount == 1)
        #expect(enabled.unregisterCount == 0)
        #expect(enabled.failure == nil)
        #expect(disabled.health == .notRegistered)
        #expect(disabled.registerCount == 0)
        #expect(disabled.unregisterCount == 1)
        #expect(disabled.failure == nil)
    }

    @Test @MainActor func repeatedEnableIsIdempotent() {
        let snapshot = LaunchAtLoginServiceFixtures.enablingAlreadyEnabledApplication()

        #expect(snapshot.health == .enabled)
        #expect(snapshot.registerCount == 0)
        #expect(snapshot.failure == nil)
    }

    @Test @MainActor func approvalRequiredIsReportedWithAnActionableRecovery() {
        let snapshot = LaunchAtLoginServiceFixtures.approvalRequiredAfterRegistration()

        #expect(snapshot.health == .requiresApproval)
        #expect(snapshot.registerCount == 1)
        #expect(snapshot.failure?.message.contains("requires approval") == true)
        #expect(snapshot.failure?.recovery.contains("Login Items") == true)
    }

    @Test @MainActor func bareExecutableDoesNotClaimRegistrationSucceeded() {
        let snapshot = LaunchAtLoginServiceFixtures.bareExecutableCannotRegister()

        #expect(snapshot.registerCount == 0)
        #expect(snapshot.health == .unavailable(
            "Launch at Login requires the packaged Agent Pulse app. Build and open the application bundle instead of running the bare Swift package executable."
        ))
        #expect(snapshot.failure?.recovery.contains("packaged Agent Pulse app") == true)
    }

    @Test @MainActor func missingApplicationAndRegistrationErrorsStayActionable() {
        let missing = LaunchAtLoginServiceFixtures.missingApplicationCannotRegister()
        let rejected = LaunchAtLoginServiceFixtures.registrationFailure()

        #expect(missing.registerCount == 0)
        #expect(missing.failure?.message.contains("could not find") == true)
        #expect(missing.failure?.recovery.contains("Applications folder") == true)
        #expect(rejected.registerCount == 1)
        #expect(rejected.health == .notRegistered)
        #expect(rejected.failure?.message.contains("could not be added") == true)
        #expect(rejected.failure?.recovery.contains("rejected the request") == true)
    }

    @Test func presentationReflectsRegistrationAndDevelopmentStates() {
        let snapshot = LaunchAtLoginServiceFixtures.presentation()

        #expect(!snapshot.notRegisteredIsOn)
        #expect(snapshot.enabledIsOn)
        #expect(snapshot.approvalIsOn)
        #expect(!snapshot.unavailableCanChange)
        #expect(snapshot.developmentGuidance == "Development build")
    }
}
