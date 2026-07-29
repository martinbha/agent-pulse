import Testing

@testable import AgentPulseCore

@MainActor
@Suite struct NotificationPreferencesTests {
    @Test func missingPreferenceDefaultsToSilent() {
        let defaults = NotificationPreferencesFixtures.makeDefaults()

        let preferences = NotificationPreferences(defaults: defaults)

        #expect(!preferences.playsSounds)
        #expect(defaults.object(forKey: "notifications.playSounds") == nil)
    }

    @Test func changesApplyImmediatelyAndPersistAcrossReloads() {
        let defaults = NotificationPreferencesFixtures.makeDefaults()
        let preferences = NotificationPreferences(defaults: defaults)

        #expect(preferences.setPlaysSounds(true))
        #expect(preferences.playsSounds)
        #expect(!preferences.setPlaysSounds(true))
        #expect(NotificationPreferences(defaults: defaults).playsSounds)

        #expect(preferences.setPlaysSounds(false))
        #expect(!preferences.playsSounds)
        #expect(!NotificationPreferences(defaults: defaults).playsSounds)
    }
}
