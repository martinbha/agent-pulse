import Testing

@testable import AgentPulseBridgeSupport

@Suite struct BridgeDiagnosticsTests {
    @Test func parsesCommands() {
        #expect(BridgeCommand.parse([]) == .none)
        #expect(BridgeCommand.parse(["--version"]) == .version)
        #expect(BridgeCommand.parse(["--doctor"]) == .doctor(agent: nil))
        #expect(BridgeCommand.parse(["--doctor", "claude"]) == .doctor(agent: "claude"))
        #expect(BridgeCommand.parse(["--doctor", "unknown"]) == .none)
        #expect(BridgeCommand.parse(["--unknown"]) == .none)
        #expect(BridgeCommand.parse(["unknown"]) == .none)
        #expect(BridgeCommand.parse(["claude"]) == .hook(agent: "claude"))
        #expect(BridgeCommand.parse(["codex"]) == .hook(agent: "codex"))
    }

    @Test func resolvesVersionFromSidecarThenBundle() {
        #expect(
            BridgeVersion.resolved(sidecarVersion: " 1.2.3\n", bundleVersion: "9.9.9") == "1.2.3"
        )
        #expect(BridgeVersion.resolved(sidecarVersion: nil, bundleVersion: "2.0.0") == "2.0.0")
        #expect(BridgeVersion.resolved(sidecarVersion: " ", bundleVersion: nil) == "development")
    }

    @Test func redactsSecretsAndRotatesOwnerOnlyLog() throws {
        let snapshot = try BridgeDiagnosticsFixtures.loggingSnapshot()

        #expect(snapshot.current.contains("second failure causes rotation"))
        #expect(snapshot.backup.contains("<redacted>"))
        #expect(!snapshot.backup.contains("secret-token"))
        #expect(snapshot.permissions == 0o600)
        #expect(snapshot.directoryPermissions == 0o700)
    }

    @Test func mapsCommonNetworkFailures() {
        #expect(
            BridgeDiagnosticsFixtures.diagnosticMessage(for: .timedOut)
                == "The local server timed out."
        )
        #expect(
            BridgeDiagnosticsFixtures.diagnosticMessage(for: .cannotConnectToHost)
                == "The local server is not reachable. Make sure Agent Pulse is running."
        )
    }

    @Test func mapsRejectedTokenToRepairGuidance() {
        #expect(
            BridgeDiagnosticMessage.describe(BridgeRequestError.rejected(401))
                == "The local server rejected the bridge token. Run setup repair."
        )
    }

    @Test func doctorUsesDistinctFailureExitCodes() {
        #expect(
            BridgeDoctorExitCode.forError(BridgeConfigurationError.unreadable("config"))
                == BridgeDoctorExitCode.invalidConfiguration
        )
        #expect(
            BridgeDiagnosticsFixtures.unavailableDoctorExitCode()
                == BridgeDoctorExitCode.serverUnavailable
        )
        #expect(
            BridgeDoctorExitCode.forError(BridgeRequestError.rejected(401))
                == BridgeDoctorExitCode.authorizationFailure
        )
        #expect(
            BridgeDoctorExitCode.forError(BridgeRequestError.rejected(500))
                == BridgeDoctorExitCode.invalidServerResponse
        )
    }
}
