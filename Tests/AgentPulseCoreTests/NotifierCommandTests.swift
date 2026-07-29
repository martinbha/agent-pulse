import Testing

@testable import AgentPulseCore

@Suite struct NotifierCommandTests {
    @Test func roundTripsFullCommand() {
        let command = NotifierCommand(
            title: "Claude has begun Inferring",
            body: "agent-pulse · PreToolUse",
            hostBundleID: "com.googlecode.iterm2",
            playsSound: true
        )
        #expect(command.argumentList().contains(NotifierCommand.soundArgument))
        #expect(NotifierCommand.parse(command.argumentList()) == command)
    }

    @Test func roundTripsWithoutHostBundleID() {
        let command = NotifierCommand(title: "Codex has finished Compiling", body: "demo · Stop")
        #expect(NotifierCommand.parse(command.argumentList()) == command)
    }

    @Test func roundTripsContextualAuthorizationRequest() {
        let command = NotifierCommand(
            title: "Claude notification test",
            body: "Sent from Setup",
            requestsAuthorization: true
        )

        #expect(command.argumentList().contains(NotifierCommand.requestAuthorizationArgument))
        #expect(NotifierCommand.parse(command.argumentList()) == command)
    }

    @Test func omitsEmptyHostBundleIDFromArguments() {
        let command = NotifierCommand(title: "Title", body: "Body", hostBundleID: "")
        #expect(!command.argumentList().contains("--host-bundle-id"))
    }

    @Test func normalizesEmptyHostBundleIDToNil() {
        #expect(NotifierCommand(title: "Title", body: "Body", hostBundleID: "").hostBundleID == nil)
    }

    @Test func parseRequiresTitle() {
        #expect(NotifierCommand.parse(["--body", "Body"]) == nil)
    }

    @Test func parseTreatsNoArgumentsAsInteractionLaunch() {
        #expect(NotifierCommand.parse([]) == nil)
    }

    @Test func parseDefaultsMissingBodyToEmpty() {
        let command = NotifierCommand.parse(["--title", "Title"])
        #expect(command?.body == "")
        #expect(command?.playsSound == false)
    }

    @Test func parseSkipsUnknownTokens() {
        let command = NotifierCommand.parse(["-psn_0_12345", "--title", "Title", "--body", "Body"])
        #expect(command == NotifierCommand(title: "Title", body: "Body"))
    }

    @Test func routineNotificationsNeverRequestUndeterminedPermission() {
        #expect(
            NotifierAuthorizationPolicy.action(
                for: .notDetermined,
                requestsAuthorization: false
            ) == .deny
        )
        #expect(
            NotifierAuthorizationPolicy.action(
                for: .notDetermined,
                requestsAuthorization: true
            ) == .request
        )
    }

    @Test func contentAndForegroundPresentationHonorSoundFlag() {
        let silent = NotifierCommand(title: "Title", body: "Body")
            .makeNotificationContent()
        let audible = NotifierCommand(title: "Title", body: "Body", playsSound: true)
            .makeNotificationContent()

        #expect(silent.sound == nil)
        #expect(audible.sound != nil)
        #expect(NotifierPresentationPolicy.options(for: silent).contains(.banner))
        #expect(!NotifierPresentationPolicy.options(for: silent).contains(.sound))
        #expect(NotifierPresentationPolicy.options(for: audible).contains(.sound))
    }

    @Test func authorizationRequestsSoundOnlyWhenEnabled() {
        let silent = NotifierAuthorizationOptionsPolicy.options(playsSound: false)
        let audible = NotifierAuthorizationOptionsPolicy.options(playsSound: true)

        #expect(silent.contains(.alert))
        #expect(!silent.contains(.sound))
        #expect(audible.contains(.alert))
        #expect(audible.contains(.sound))
    }

    @Test func authorizedStatesPostWhileDeniedAndUnknownStatesDoNot() {
        for status in [
            NotifierAuthorizationStatus.authorized,
            .provisional,
            .ephemeral,
        ] {
            #expect(
                NotifierAuthorizationPolicy.action(
                    for: status,
                    requestsAuthorization: false
                ) == .post
            )
        }
        for status in [
            NotifierAuthorizationStatus.denied,
            .unknown,
        ] {
            #expect(
                NotifierAuthorizationPolicy.action(
                    for: status,
                    requestsAuthorization: true
                ) == .deny
            )
        }
    }
}
