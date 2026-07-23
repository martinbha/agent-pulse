import Foundation
import ServiceManagement

enum LaunchAtLoginRegistrationStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unavailable(String)
}

struct LaunchAtLoginFailure: LocalizedError, Equatable {
    let message: String
    let recovery: String

    var errorDescription: String? { message }
    var recoverySuggestion: String? { recovery }
}

@MainActor
struct LaunchAtLoginService {
    typealias StatusProvider = () -> LaunchAtLoginRegistrationStatus
    typealias Mutation = () throws -> Void

    private let application: ApplicationLocationHealth
    private let statusProvider: StatusProvider
    private let register: Mutation
    private let unregister: Mutation

    init(
        application: ApplicationLocationHealth,
        statusProvider: @escaping StatusProvider,
        register: @escaping Mutation,
        unregister: @escaping Mutation
    ) {
        self.application = application
        self.statusProvider = statusProvider
        self.register = register
        self.unregister = unregister
    }

    static func live(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleURL: URL = Bundle.main.bundleURL
    ) -> LaunchAtLoginService {
        let application = SetupHealthClassifier.applicationLocation(
            bundleURL: bundleURL,
            homeDirectory: homeDirectory
        )
        let service = SMAppService.mainApp
        return LaunchAtLoginService(
            application: application,
            statusProvider: {
                registrationStatus(from: service.status)
            },
            register: {
                try service.register()
            },
            unregister: {
                try service.unregister()
            }
        )
    }

    var health: LaunchAtLoginHealth {
        if let unavailableReason {
            return .unavailable(unavailableReason)
        }

        switch statusProvider() {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .unavailable(let reason): return .unavailable(reason)
        }
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginHealth {
        if let unavailableReason {
            throw LaunchAtLoginFailure(
                message: "Launch at Login is unavailable.",
                recovery: unavailableReason
            )
        }

        let initialStatus = statusProvider()
        if enabled {
            switch initialStatus {
            case .enabled:
                return .enabled
            case .requiresApproval:
                throw approvalFailure
            case .notFound:
                throw notFoundFailure
            case .unavailable(let reason):
                throw unavailableFailure(reason)
            case .notRegistered:
                do {
                    try register()
                } catch {
                    throw LaunchAtLoginFailure(
                        message: "Agent Pulse could not be added to Launch at Login.",
                        recovery: "Move Agent Pulse to an Applications folder, reopen it, and retry. \(error.localizedDescription)"
                    )
                }
            }
        } else {
            switch initialStatus {
            case .notRegistered:
                return .notRegistered
            case .notFound:
                throw notFoundFailure
            case .unavailable(let reason):
                throw unavailableFailure(reason)
            case .enabled, .requiresApproval:
                do {
                    try unregister()
                } catch {
                    throw LaunchAtLoginFailure(
                        message: "Agent Pulse could not be removed from Launch at Login.",
                        recovery: "Open System Settings → General → Login Items and remove Agent Pulse, then return and refresh. \(error.localizedDescription)"
                    )
                }
            }
        }

        return try verifiedHealth(expectedEnabled: enabled)
    }

    private var unavailableReason: String? {
        switch application {
        case .unbundled:
            return "Launch at Login requires the packaged Agent Pulse app. Build and open the application bundle instead of running the bare Swift package executable."
        case .translocated:
            return "Move Agent Pulse to /Applications or ~/Applications, reopen it, and retry."
        case .applications, .userApplications, .other:
            return nil
        }
    }

    private func verifiedHealth(expectedEnabled: Bool) throws -> LaunchAtLoginHealth {
        let current = statusProvider()
        switch current {
        case .enabled where expectedEnabled:
            return .enabled
        case .notRegistered where !expectedEnabled:
            return .notRegistered
        case .requiresApproval where expectedEnabled:
            throw approvalFailure
        case .notFound:
            throw notFoundFailure
        case .unavailable(let reason):
            throw unavailableFailure(reason)
        default:
            throw LaunchAtLoginFailure(
                message: expectedEnabled
                    ? "Launch at Login did not become enabled."
                    : "Launch at Login remained registered.",
                recovery: "Open System Settings → General → Login Items, verify the Agent Pulse entry, then return and refresh."
            )
        }
    }

    private var approvalFailure: LaunchAtLoginFailure {
        LaunchAtLoginFailure(
            message: "Launch at Login requires approval.",
            recovery: "Open System Settings → General → Login Items, allow Agent Pulse, then return and refresh."
        )
    }

    private var notFoundFailure: LaunchAtLoginFailure {
        LaunchAtLoginFailure(
            message: "macOS could not find the Agent Pulse login item.",
            recovery: "Move Agent Pulse to an Applications folder, reopen it, and retry."
        )
    }

    private func unavailableFailure(_ reason: String) -> LaunchAtLoginFailure {
        LaunchAtLoginFailure(
            message: "Launch at Login is unavailable.",
            recovery: reason
        )
    }

    private static func registrationStatus(
        from status: SMAppService.Status
    ) -> LaunchAtLoginRegistrationStatus {
        switch status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default:
            return .unavailable("macOS returned an unknown Launch at Login state.")
        }
    }
}

enum LaunchAtLoginPresentation {
    static func isOn(_ health: LaunchAtLoginHealth) -> Bool {
        switch health {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound, .unavailable:
            return false
        }
    }

    static func canChange(_ health: LaunchAtLoginHealth) -> Bool {
        switch health {
        case .notRegistered, .enabled, .requiresApproval:
            return true
        case .notFound, .unavailable:
            return false
        }
    }

    static func label(_ health: LaunchAtLoginHealth) -> String {
        switch health {
        case .notRegistered: return "Off"
        case .enabled: return "On"
        case .requiresApproval: return "Approval required"
        case .notFound: return "App not found"
        case .unavailable: return "Unavailable"
        }
    }

    static func guidance(_ health: LaunchAtLoginHealth) -> String {
        switch health {
        case .notRegistered:
            return "Start Agent Pulse automatically after you sign in to this Mac."
        case .enabled:
            return "Agent Pulse will start automatically after you sign in."
        case .requiresApproval:
            return "Allow Agent Pulse in System Settings → General → Login Items."
        case .notFound:
            return "Move Agent Pulse to an Applications folder, reopen it, and retry."
        case .unavailable(let reason):
            return reason
        }
    }
}
