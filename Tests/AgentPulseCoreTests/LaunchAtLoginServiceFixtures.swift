import Foundation

@testable import AgentPulseCore

struct LaunchAtLoginMutationSnapshot {
    let health: LaunchAtLoginHealth?
    let registerCount: Int
    let unregisterCount: Int
    let failure: LaunchAtLoginFailure?
}

struct LaunchAtLoginPresentationSnapshot {
    let notRegisteredIsOn: Bool
    let enabledIsOn: Bool
    let approvalIsOn: Bool
    let unavailableCanChange: Bool
    let developmentGuidance: String
}

@MainActor
private final class LaunchAtLoginServiceState {
    var status: LaunchAtLoginRegistrationStatus
    var registerCount = 0
    var unregisterCount = 0
    var registerError: Error?
    var unregisterError: Error?
    var statusAfterRegisterError: LaunchAtLoginRegistrationStatus?
    var registeredStatus: LaunchAtLoginRegistrationStatus = .enabled

    init(status: LaunchAtLoginRegistrationStatus) {
        self.status = status
    }

    func makeService(
        application: ApplicationLocationHealth = .applications(
            URL(fileURLWithPath: "/Applications/Agent Pulse.app")
        )
    ) -> LaunchAtLoginService {
        LaunchAtLoginService(
            application: application,
            statusProvider: { self.status },
            register: {
                self.registerCount += 1
                if let registerError = self.registerError {
                    if let statusAfterRegisterError = self.statusAfterRegisterError {
                        self.status = statusAfterRegisterError
                    }
                    throw registerError
                }
                self.status = self.registeredStatus
            },
            unregister: {
                self.unregisterCount += 1
                if let unregisterError = self.unregisterError {
                    throw unregisterError
                }
                self.status = .notRegistered
            }
        )
    }
}

private struct SampleLaunchAtLoginError: LocalizedError {
    let errorDescription: String? = "The service rejected the request."
}

enum LaunchAtLoginServiceFixtures {
    @MainActor
    static func enablingPackagedApplication() -> LaunchAtLoginMutationSnapshot {
        let state = LaunchAtLoginServiceState(status: .notRegistered)
        let service = state.makeService()
        return capture(service: service, state: state, enabled: true)
    }

    @MainActor
    static func disablingPackagedApplication() -> LaunchAtLoginMutationSnapshot {
        let state = LaunchAtLoginServiceState(status: .enabled)
        let service = state.makeService()
        return capture(service: service, state: state, enabled: false)
    }

    @MainActor
    static func enablingAlreadyEnabledApplication() -> LaunchAtLoginMutationSnapshot {
        let state = LaunchAtLoginServiceState(status: .enabled)
        let service = state.makeService()
        return capture(service: service, state: state, enabled: true)
    }

    @MainActor
    static func approvalRequiredAfterRegistration() -> LaunchAtLoginMutationSnapshot {
        let state = LaunchAtLoginServiceState(status: .notRegistered)
        state.registeredStatus = .requiresApproval
        let service = state.makeService()
        return capture(service: service, state: state, enabled: true)
    }

    @MainActor
    static func bareExecutableCannotRegister() -> LaunchAtLoginMutationSnapshot {
        let state = LaunchAtLoginServiceState(status: .notRegistered)
        let service = state.makeService(
            application: .unbundled(URL(fileURLWithPath: "/tmp/agent-pulse"))
        )
        return capture(service: service, state: state, enabled: true)
    }

    @MainActor
    static func missingApplicationCannotRegister() -> LaunchAtLoginMutationSnapshot {
        let state = LaunchAtLoginServiceState(status: .notFound)
        let service = state.makeService()
        return capture(service: service, state: state, enabled: true)
    }

    @MainActor
    static func registrationFailure() -> LaunchAtLoginMutationSnapshot {
        let state = LaunchAtLoginServiceState(status: .notRegistered)
        state.registerError = SampleLaunchAtLoginError()
        let service = state.makeService()
        return capture(service: service, state: state, enabled: true)
    }

    @MainActor
    static func registrationFailureRequiringApproval() -> LaunchAtLoginMutationSnapshot {
        let state = LaunchAtLoginServiceState(status: .notRegistered)
        state.registerError = SampleLaunchAtLoginError()
        state.statusAfterRegisterError = .requiresApproval
        let service = state.makeService()
        return capture(service: service, state: state, enabled: true)
    }

    static func presentation() -> LaunchAtLoginPresentationSnapshot {
        LaunchAtLoginPresentationSnapshot(
            notRegisteredIsOn: LaunchAtLoginPresentation.isOn(.notRegistered),
            enabledIsOn: LaunchAtLoginPresentation.isOn(.enabled),
            approvalIsOn: LaunchAtLoginPresentation.isOn(.requiresApproval),
            unavailableCanChange: LaunchAtLoginPresentation.canChange(
                .unavailable("Development build")
            ),
            developmentGuidance: LaunchAtLoginPresentation.guidance(
                .unavailable("Development build")
            )
        )
    }

    @MainActor
    private static func capture(
        service: LaunchAtLoginService,
        state: LaunchAtLoginServiceState,
        enabled: Bool
    ) -> LaunchAtLoginMutationSnapshot {
        do {
            let health = try service.setEnabled(enabled)
            return LaunchAtLoginMutationSnapshot(
                health: health,
                registerCount: state.registerCount,
                unregisterCount: state.unregisterCount,
                failure: nil
            )
        } catch let failure as LaunchAtLoginFailure {
            return LaunchAtLoginMutationSnapshot(
                health: service.health,
                registerCount: state.registerCount,
                unregisterCount: state.unregisterCount,
                failure: failure
            )
        } catch {
            return LaunchAtLoginMutationSnapshot(
                health: service.health,
                registerCount: state.registerCount,
                unregisterCount: state.unregisterCount,
                failure: LaunchAtLoginFailure(
                    message: error.localizedDescription,
                    recovery: ""
                )
            )
        }
    }
}
