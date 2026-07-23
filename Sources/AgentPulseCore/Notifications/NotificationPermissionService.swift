import Darwin
import Foundation
import UserNotifications

struct NotificationPermissionFailure: LocalizedError, Equatable {
    let message: String
    let recovery: String

    var errorDescription: String? { message }
    var recoverySuggestion: String? { recovery }
}

struct NotificationHelperProcessResult: Equatable, Sendable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String
}

@MainActor
struct NotificationPermissionService {
    typealias MainStatusProvider = () async -> NotificationAuthorizationHealth
    typealias HelperStatusProvider = (AgentKind) async -> NotificationAuthorizationHealth
    typealias TestSender = (AgentKind) async throws -> Void

    private let mainStatusProvider: MainStatusProvider
    private let helperStatusProvider: HelperStatusProvider
    private let testSender: TestSender

    init(
        mainStatusProvider: @escaping MainStatusProvider,
        helperStatusProvider: @escaping HelperStatusProvider,
        testSender: @escaping TestSender
    ) {
        self.mainStatusProvider = mainStatusProvider
        self.helperStatusProvider = helperStatusProvider
        self.testSender = testSender
    }

    static func live(
        center: UNUserNotificationCenter = .current(),
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> NotificationPermissionService {
        NotificationPermissionService(
            mainStatusProvider: {
                let settings = await center.notificationSettings()
                return health(from: NotifierAuthorizationStatus(settings.authorizationStatus))
            },
            helperStatusProvider: { agent in
                guard let executableURL = NotificationHelperLocator.executableURL(
                    for: agent,
                    bundleURL: bundleURL,
                    fileManager: fileManager
                ) else {
                    return .unavailable(
                        "The packaged \(agent.displayName) notification helper is unavailable."
                    )
                }
                return await helperHealth(executableURL: executableURL)
            },
            testSender: { agent in
                if let executableURL = NotificationHelperLocator.executableURL(
                    for: agent,
                    bundleURL: bundleURL,
                    fileManager: fileManager
                ) {
                    try await sendHelperTest(
                        agent: agent,
                        executableURL: executableURL
                    )
                } else if bundleURL.pathExtension.lowercased() != "app" {
                    try await sendMainAppTest(
                        agent: agent,
                        center: center
                    )
                } else {
                    throw NotificationPermissionFailure(
                        message: "The \(agent.displayName) notification sender is missing.",
                        recovery: "Reinstall or rebuild the complete Agent Pulse app bundle, then retry."
                    )
                }
            }
        )
    }

    func mainHealth() async -> NotificationAuthorizationHealth {
        await mainStatusProvider()
    }

    func helperHealth(for agent: AgentKind) async -> NotificationAuthorizationHealth {
        await helperStatusProvider(agent)
    }

    func sendTest(for agent: AgentKind) async throws {
        try await testSender(agent)
    }

    nonisolated static func health(
        from status: NotifierAuthorizationStatus
    ) -> NotificationAuthorizationHealth {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        case .unknown:
            return .unavailable("macOS returned an unknown notification authorization state.")
        }
    }

    nonisolated static func decodeHelperStatus(
        _ output: String
    ) -> NotificationAuthorizationHealth {
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let status = NotifierAuthorizationStatus(rawValue: value) else {
            return .unavailable("The notification helper returned an invalid authorization state.")
        }
        return health(from: status)
    }

    private static func helperHealth(executableURL: URL) async -> NotificationAuthorizationHealth {
        do {
            let result = try await runHelper(
                executableURL: executableURL,
                arguments: [NotifierCommand.authorizationStatusArgument],
                timeout: 3
            )
            guard result.terminationStatus == 0 else {
                return .unavailable(
                    result.standardError.isEmpty
                        ? "The notification helper status check failed."
                        : result.standardError
                )
            }
            return decodeHelperStatus(result.standardOutput)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    private static func sendHelperTest(
        agent: AgentKind,
        executableURL: URL
    ) async throws {
        let command = NotifierCommand(
            title: "\(agent.notificationName) notification test",
            body: "This test authorizes and verifies the \(agent.displayName) notification sender.",
            requestsAuthorization: true
        )
        let result = try await runHelper(
            executableURL: executableURL,
            arguments: command.argumentList(),
            timeout: NotificationTiming.posterDeadline + 2
        )
        switch result.terminationStatus {
        case 0:
            return
        case 2:
            throw NotificationPermissionFailure(
                message: "\(agent.displayName) notifications are not authorized.",
                recovery: "Open System Settings → Notifications, allow Agent Pulse \(agent.displayName), then retry the test."
            )
        case 3:
            throw NotificationPermissionFailure(
                message: "The \(agent.displayName) notification permission request timed out.",
                recovery: "Return to Agent Pulse and retry the test, then respond to the macOS permission prompt."
            )
        default:
            throw NotificationPermissionFailure(
                message: "The \(agent.displayName) test notification could not be delivered.",
                recovery: result.standardError.isEmpty
                    ? "Open System Settings → Notifications, review the Agent Pulse \(agent.displayName) entry, then retry."
                    : result.standardError
            )
        }
    }

    private static func sendMainAppTest(
        agent: AgentKind,
        center: UNUserNotificationCenter
    ) async throws {
        let settings = await center.notificationSettings()
        let status = NotifierAuthorizationStatus(settings.authorizationStatus)
        let action = NotifierAuthorizationPolicy.action(
            for: status,
            requestsAuthorization: true
        )

        if action == .deny {
            throw NotificationPermissionFailure(
                message: "Agent Pulse notifications are not authorized.",
                recovery: "Open System Settings → Notifications, allow Agent Pulse, then retry the test."
            )
        }
        if action == .request {
            let granted: Bool
            do {
                granted = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                throw NotificationPermissionFailure(
                    message: "Agent Pulse could not request notification permission.",
                    recovery: "Open System Settings → Notifications, allow Agent Pulse, then retry. \(error.localizedDescription)"
                )
            }
            guard granted else {
                throw NotificationPermissionFailure(
                    message: "Agent Pulse notifications were not allowed.",
                    recovery: "Open System Settings → Notifications, allow Agent Pulse, then retry the test."
                )
            }
        }

        let command = NotifierCommand(
            title: "\(agent.notificationName) notification test",
            body: "Development fallback notification sent by Agent Pulse."
        )
        let identifier = "agent-pulse-test-\(agent.rawValue)-\(UUID().uuidString)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: command.makeNotificationContent(),
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            throw NotificationPermissionFailure(
                message: "The development fallback notification could not be delivered.",
                recovery: "Open System Settings → Notifications, review the Agent Pulse entry, then retry. \(error.localizedDescription)"
            )
        }
        Task {
            try? await Task.sleep(for: .seconds(NotificationTiming.bannerDismissalDelay))
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }

    private static func runHelper(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> NotificationHelperProcessResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                usleep(50_000)
            }
            if process.isRunning {
                process.terminate()
                let terminationDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < terminationDeadline {
                    usleep(50_000)
                }
                if process.isRunning {
                    process.interrupt()
                    let interruptionDeadline = Date().addingTimeInterval(1)
                    while process.isRunning && Date() < interruptionDeadline {
                        usleep(50_000)
                    }
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                process.waitUntilExit()
                throw NotificationPermissionFailure(
                    message: "The notification helper did not finish.",
                    recovery: "Retry the operation and respond to any visible macOS permission prompt."
                )
            }

            return NotificationHelperProcessResult(
                terminationStatus: process.terminationStatus,
                standardOutput: String(
                    decoding: stdout.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                ).trimmingCharacters(in: .whitespacesAndNewlines),
                standardError: String(
                    decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.value
    }
}

enum NotificationHelperLocator {
    static func executableURL(
        for agent: AgentKind,
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> URL? {
        let name = agent.notifierHelperName
        let url = bundleURL
            .appendingPathComponent("Contents/Helpers/\(name).app/Contents/MacOS/\(name)")
        guard fileManager.isExecutableFile(atPath: url.path) else {
            return nil
        }
        return url
    }
}
