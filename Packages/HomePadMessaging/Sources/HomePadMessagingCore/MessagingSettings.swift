import Foundation
import HomePadCore

/// Preferences this package reads. The user changes them in the system Settings app; nothing in
/// the package writes them.
public enum MessagingSettings {
    public static let pane = "Messages & Projection"

    public static let projectMessages = SettingKey<Bool>("messaging.projectMessages", default: true)
    public static let projectCalendar = SettingKey<Bool>("messaging.projectCalendar", default: true)
    public static let projectReminders = SettingKey<Bool>("messaging.projectReminders", default: true)
    public static let projectNowPlaying = SettingKey<Bool>("messaging.projectNowPlaying", default: true)
    public static let showMessagePreviews = SettingKey<Bool>("messaging.showPreviews", default: true)
    public static let retentionHours = SettingKey<Int>("messaging.retentionHours", default: 24)
    public static let householdNotes = SettingKey<Bool>("messaging.householdNotes", default: true)
    public static let hubMessagesAccountOwner = SettingKey<String>("messaging.hubMessagesOwner", default: "")
    /// Read by the iMessage extension from the app group defaults.
    public static let suggestRecentPages = SettingKey<Bool>("messaging.suggestRecentPages", default: true)

    public static let retentionHourOptions = [1, 8, 24, 72]

    public static let descriptors: [SettingDescriptor] = [
        SettingDescriptor(projectMessages, title: "Show Messages on HomePad", pane: pane),
        SettingDescriptor(projectCalendar, title: "Show Calendar on HomePad", pane: pane),
        SettingDescriptor(projectReminders, title: "Show Reminders on HomePad", pane: pane),
        SettingDescriptor(
            projectNowPlaying,
            title: "Show Now Playing on HomePad",
            pane: pane,
            footer: "Set these on your iPhone. They choose which of this iPhone's apps appear on a nearby HomePad. Messages, Calendar, and Reminders appear only while HomePad recognizes your face."
        ),
        SettingDescriptor(
            showMessagePreviews,
            title: "Show Message Previews",
            pane: pane,
            footer: "Set this on your iPhone. When off, the conversation list on HomePad shows who wrote, and the text appears only after you open the conversation."
        ),
        SettingDescriptor(
            retentionHours,
            title: "Keep Relayed Messages",
            pane: pane,
            options: [
                .init(title: "1 Hour", value: "1"),
                .init(title: "8 Hours", value: "8"),
                .init(title: "1 Day", value: "24"),
                .init(title: "3 Days", value: "72"),
            ],
            footer: "Relayed messages are kept in memory on your iPhone for this long and are never saved on HomePad."
        ),
        SettingDescriptor(
            householdNotes,
            title: "Household Notes",
            pane: pane,
            footer: "When off, this device neither sends nor shows household notes."
        ),
        SettingDescriptor(
            hubMessagesAccountOwner,
            title: "Messages on This iPad Belongs To",
            pane: pane,
            footer: "Set this on the HomePad iPad. Enter the name of the household member whose Messages account is signed in on this iPad. Only that person can send replies from the iPad. Everyone else confirms replies on their iPhone. Leave empty to always use the iPhone."
        ),
        SettingDescriptor(
            suggestRecentPages,
            title: "Suggest Recent Pages in Messages",
            pane: pane,
            footer: "When on, the HomePad app in Messages offers pages you recently sent to a HomePad."
        ),
    ]

    /// A stored value that is not one of the offered options falls back to the default.
    public static func retention(hours: Int) -> TimeInterval {
        let valid = retentionHourOptions.contains(hours) ? hours : retentionHours.defaultValue
        return TimeInterval(valid) * 60 * 60
    }

    /// The built-in apps a companion should project, given the four switches.
    public static func enabledAppIDs(messages: Bool, calendar: Bool, reminders: Bool, nowPlaying: Bool) -> Set<String> {
        var ids: Set<String> = []
        if messages { ids.insert(BuiltInProjectedApp.messagesID) }
        if calendar { ids.insert(BuiltInProjectedApp.calendarID) }
        if reminders { ids.insert(BuiltInProjectedApp.remindersID) }
        if nowPlaying { ids.insert(BuiltInProjectedApp.nowPlayingID) }
        return ids
    }
}
