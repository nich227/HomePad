import Foundation
import HomePadCore
import Testing
@testable import HomePadMessagingCore

@Suite struct MessagingSettingsTests {
    @Test func descriptors_whenListed_thenCoverEveryKeyOnceInTheMessagingPane() {
        let names = MessagingSettings.descriptors.map(\.name)
        #expect(names == [
            "messaging.projectMessages", "messaging.projectCalendar", "messaging.projectReminders", "messaging.projectNowPlaying",
            "messaging.showPreviews", "messaging.retentionHours", "messaging.householdNotes", "messaging.hubMessagesOwner",
            "messaging.suggestRecentPages",
        ])
        #expect(Set(names).count == names.count)
        #expect(MessagingSettings.descriptors.allSatisfy { $0.pane == "Messages & Projection" && $0.name.hasPrefix("messaging.") })
    }

    @Test func descriptors_whenCompared_thenDefaultsMatchTheKeys() {
        let byName = Dictionary(uniqueKeysWithValues: MessagingSettings.descriptors.map { ($0.name, $0) })
        #expect(byName[MessagingSettings.projectMessages.name]?.defaultValue == .bool(true))
        #expect(byName[MessagingSettings.projectMessages.name]?.control == .toggle)
        #expect(byName[MessagingSettings.showMessagePreviews.name]?.defaultValue == .bool(true))
        #expect(byName[MessagingSettings.householdNotes.name]?.defaultValue == .bool(true))
        #expect(byName[MessagingSettings.suggestRecentPages.name]?.defaultValue == .bool(true))
        #expect(byName[MessagingSettings.hubMessagesAccountOwner.name]?.defaultValue == .string(""))
        #expect(byName[MessagingSettings.hubMessagesAccountOwner.name]?.control == .text)
        #expect(byName[MessagingSettings.retentionHours.name]?.defaultValue == .integer(24))
    }

    @Test func descriptors_whenRetentionIsAChoice_thenOptionsMatchTheAcceptedHours() {
        let retention = MessagingSettings.descriptors.first { $0.name == MessagingSettings.retentionHours.name }
        guard case .choice(let options)? = retention?.control else { Issue.record("choice expected"); return }
        #expect(options.map(\.value) == MessagingSettings.retentionHourOptions.map(String.init))
        #expect(MessagingSettings.retentionHourOptions.contains(MessagingSettings.retentionHours.defaultValue))
    }

    @Test func retention_whenHoursIsAnOption_thenConvertsToSeconds() {
        #expect(MessagingSettings.retention(hours: 1) == 3600)
        #expect(MessagingSettings.retention(hours: 72) == 259_200)
    }

    @Test func retention_whenHoursIsNotAnOption_thenFallsBackToDefault() {
        #expect(MessagingSettings.retention(hours: 0) == 86_400)
        #expect(MessagingSettings.retention(hours: 100_000) == 86_400)
    }

    @Test func enabledAppIDs_whenSwitchesVary_thenOnlyEnabledAppsAreListed() {
        #expect(MessagingSettings.enabledAppIDs(messages: true, calendar: true, reminders: true, nowPlaying: true) == ["messages", "calendar", "reminders", "nowPlaying"])
        #expect(MessagingSettings.enabledAppIDs(messages: false, calendar: true, reminders: false, nowPlaying: true) == ["calendar", "nowPlaying"])
        #expect(MessagingSettings.enabledAppIDs(messages: false, calendar: false, reminders: false, nowPlaying: false).isEmpty)
    }
}
