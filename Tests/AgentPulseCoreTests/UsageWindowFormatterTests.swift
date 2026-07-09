import Testing

@testable import AgentPulseCore

@Suite struct UsagePercentFormattingTests {
    @Test func percentTextRoundsAndSuffixes() {
        #expect(UsageWindowFormatter.percentText(42.4) == "42%")
        #expect(UsageWindowFormatter.percentText(42.6) == "43%")
    }

    @Test func percentTextIsNilWhenMissing() {
        #expect(UsageWindowFormatter.percentText(nil) == nil)
    }

    @Test func fractionClampsToUnitRange() {
        #expect(UsageWindowFormatter.fraction(50) == 0.5)
        #expect(UsageWindowFormatter.fraction(nil) == 0)
        #expect(UsageWindowFormatter.fraction(150) == 1)
        #expect(UsageWindowFormatter.fraction(-10) == 0)
    }
}

@Suite struct UsageResetCountdownTests {
    @Test func showsDaysHoursMinutes() {
        #expect(UsageWindowFormatterFixtures.countdownDaysHoursMinutes() == "4d 5h 30m")
    }

    @Test func showsHoursAndZeroPaddedMinutes() {
        #expect(UsageWindowFormatterFixtures.countdownHoursMinutes() == "3h 06m")
    }

    @Test func showsMinutesOnlyWhenUnderAnHour() {
        #expect(UsageWindowFormatterFixtures.countdownMinutesOnly() == "05m")
    }

    @Test func showsLessThanAMinute() {
        #expect(UsageWindowFormatterFixtures.countdownUnderAMinute() == "<1m")
    }

    @Test func alreadyResetShowsLessThanAMinute() {
        #expect(UsageWindowFormatterFixtures.countdownAlreadyReset() == "<1m")
    }

    @Test func detailLineJoinsPercentAndCountdown() {
        #expect(UsageWindowFormatterFixtures.detailLineFull() == "42% · 3h 06m")
    }

    @Test func detailLineFallsBackToPercentOnly() {
        #expect(UsageWindowFormatterFixtures.detailLinePercentOnly() == "42%")
    }

    @Test func detailLineNilWhenNothingToShow() {
        #expect(UsageWindowFormatterFixtures.detailLineIsNilWhenEmpty())
    }
}

@Suite struct UsageHeaderFormattingTests {
    @Test func lastUpdatedShowsRelativeTime() {
        #expect(UsageWindowFormatterFixtures.lastUpdatedRecent().hasPrefix("Updated"))
    }

    @Test func lastUpdatedHandlesNeverUpdated() {
        #expect(UsageWindowFormatterFixtures.lastUpdatedNil() == "Not updated yet")
    }
}

@Suite struct UsageAvailabilityMessageTests {
    @Test func availableAndLoadingHaveNoMessage() {
        #expect(UsageWindowFormatter.availabilityMessage(.available) == nil)
        #expect(UsageWindowFormatter.availabilityMessage(.loading) == nil)
    }

    @Test func authStatesMapToFriendlyText() {
        #expect(UsageWindowFormatter.availabilityMessage(.missingAuth) == "Not logged in")
        #expect(UsageWindowFormatter.availabilityMessage(.notLoggedIn) == "Not logged in")
        #expect(UsageWindowFormatter.availabilityMessage(.accessDenied) == "Keychain access denied")
        #expect(UsageWindowFormatter.availabilityMessage(.sessionExpired) == "Session expired — log in again")
        #expect(UsageWindowFormatter.availabilityMessage(.notInstalled) == "CLI not found")
    }

    @Test func errorMessagePassesThrough() {
        #expect(UsageWindowFormatter.availabilityMessage(.error("boom")) == "boom")
    }
}
