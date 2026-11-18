import Foundation
import HomePadCore
import Testing
@testable import HomePadMessagingCore

@Suite struct MessagingSettingsTests {
    @Test func descriptors_whenListed_thenCoverEveryKeyOnceInOnePane() {
        let names = MessagingSettings.descriptors.map(\.name)
        #expect(names == [
            "messaging.projectCalendar", "messaging.projectReminders", "messaging.projectNowPlaying",
            "messaging.householdNotes", "messaging.suggestRecentPages",
        ])
        #expect(Set(names).count == names.count)
        #expect(MessagingSettings.pane == "iPhone Apps & Notes")
        #expect(MessagingSettings.descriptors.allSatisfy { $0.pane == MessagingSettings.pane && $0.name.hasPrefix("messaging.") })
    }

    @Test func descriptors_whenCompared_thenEveryKeyIsASwitchThatDefaultsToOn() {
        let keys = [
            MessagingSettings.projectCalendar, MessagingSettings.projectReminders, MessagingSettings.projectNowPlaying,
            MessagingSettings.householdNotes, MessagingSettings.suggestRecentPages,
        ]
        #expect(keys.map(\.name) == MessagingSettings.descriptors.map(\.name))
        #expect(keys.allSatisfy { $0.defaultValue })
        #expect(MessagingSettings.descriptors.allSatisfy { $0.defaultValue == .bool(true) && $0.control == .toggle })
    }

    @Test func enabledAppIDs_whenSwitchesVary_thenOnlyEnabledAppsAreListed() {
        #expect(MessagingSettings.enabledAppIDs(calendar: true, reminders: true, nowPlaying: true) == ["calendar", "reminders", "nowPlaying"])
        #expect(MessagingSettings.enabledAppIDs(calendar: true, reminders: false, nowPlaying: true) == ["calendar", "nowPlaying"])
        #expect(MessagingSettings.enabledAppIDs(calendar: false, reminders: true, nowPlaying: false) == ["reminders"])
        #expect(MessagingSettings.enabledAppIDs(calendar: false, reminders: false, nowPlaying: false).isEmpty)
    }
}
