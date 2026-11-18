import Foundation
import HomePadCore

/// Preferences this package reads. The user changes them in the system Settings app; nothing in
/// the package writes them.
public enum MessagingSettings {
    public static let pane = "iPhone Apps & Notes"

    public static let projectCalendar = SettingKey<Bool>("messaging.projectCalendar", default: true)
    public static let projectReminders = SettingKey<Bool>("messaging.projectReminders", default: true)
    public static let projectNowPlaying = SettingKey<Bool>("messaging.projectNowPlaying", default: true)
    public static let householdNotes = SettingKey<Bool>("messaging.householdNotes", default: true)
    /// Read by the iMessage extension from the app group defaults.
    public static let suggestRecentPages = SettingKey<Bool>("messaging.suggestRecentPages", default: true)

    public static let descriptors: [SettingDescriptor] = [
        SettingDescriptor(projectCalendar, title: "Show Calendar on HomePad", pane: pane),
        SettingDescriptor(projectReminders, title: "Show Reminders on HomePad", pane: pane),
        SettingDescriptor(
            projectNowPlaying,
            title: "Show Now Playing on HomePad",
            pane: pane,
            footer: "Set these on your iPhone. They choose which of this iPhone's apps appear on a nearby HomePad. Calendar and Reminders appear only while HomePad recognizes your face."
        ),
        SettingDescriptor(
            householdNotes,
            title: "Household Notes",
            pane: pane,
            footer: "When off, this device neither sends nor shows household notes."
        ),
        SettingDescriptor(
            suggestRecentPages,
            title: "Suggest Recent Pages in Messages",
            pane: pane,
            footer: "When on, the HomePad app in Messages offers pages you recently sent to a HomePad."
        ),
    ]

    /// The built-in apps a companion should project, given the three switches.
    public static func enabledAppIDs(calendar: Bool, reminders: Bool, nowPlaying: Bool) -> Set<String> {
        var ids: Set<String> = []
        if calendar { ids.insert(BuiltInProjectedApp.calendarID) }
        if reminders { ids.insert(BuiltInProjectedApp.remindersID) }
        if nowPlaying { ids.insert(BuiltInProjectedApp.nowPlayingID) }
        return ids
    }
}
