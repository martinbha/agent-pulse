import Testing
@testable import AgentPulseCore

@Suite struct AgentPulseVersionTests {
    @Test func usesBundleVersion() {
        #expect(AgentPulseVersion.resolved(bundleVersion: "1.2.3") == "1.2.3")
    }

    @Test func trimsBundleVersion() {
        #expect(AgentPulseVersion.resolved(bundleVersion: " 1.2.3\n") == "1.2.3")
    }

    @Test func fallsBackForMissingBundleVersion() {
        #expect(AgentPulseVersion.resolved(bundleVersion: nil) == "development")
        #expect(AgentPulseVersion.resolved(bundleVersion: "  ") == "development")
    }
}
