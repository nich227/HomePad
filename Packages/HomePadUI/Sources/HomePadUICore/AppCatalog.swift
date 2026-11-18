import Foundation
import HomePadCore

/// Who may open an app or see a widget.
public enum ContentAccess: Sendable, Equatable {
    /// Anyone in front of the hub, recognized or not.
    case guest
    /// Needs an active household profile, however it was selected.
    case member
    /// Belongs to one person. Shown redacted until their face unlocks personal content.
    case personal
    /// Household setup. Reachable only while setup mode is on in Settings.
    case setup
}

public enum HubApp: String, CaseIterable, Codable, Sendable, Identifiable {
    case clock, timers, alarms, home, music, mirror, recipes, weather, photos
    case beam, projectedApps, people, pairing, settings
    case intercom, calendar

    public var id: String { rawValue }

    public var access: ContentAccess {
        switch self {
        case .clock, .timers, .home, .music, .mirror, .recipes, .weather, .beam, .settings: .guest
        case .alarms, .photos, .intercom: .member
        case .projectedApps, .calendar: .personal
        case .people, .pairing: .setup
        }
    }

    public var requiresPersonalContent: Bool { access == .personal }

    /// Apps whose content comes from another package through a slot.
    public var isSlot: Bool {
        switch self {
        case .beam, .projectedApps, .people, .pairing, .intercom, .calendar: true
        default: false
        }
    }

    /// Apps that exist only when another package supplies them. Their icon is left out
    /// otherwise, because an icon that does nothing is worse than no icon.
    public var isOptional: Bool {
        self == .intercom || self == .calendar
    }

    public var symbolName: String {
        switch self {
        case .clock: "clock.fill"
        case .timers: "timer"
        case .alarms: "alarm.fill"
        case .home: "house.fill"
        case .music: "music.note"
        case .mirror: "person.crop.square.fill"
        case .recipes: "fork.knife"
        case .weather: "cloud.sun.fill"
        case .photos: "photo.on.rectangle.angled"
        case .beam: "dot.radiowaves.left.and.right"
        case .projectedApps: "iphone.gen3.radiowaves.left.and.right"
        case .people: "person.2.fill"
        case .pairing: "link"
        case .settings: "gearshape.fill"
        case .intercom: "waveform"
        case .calendar: "calendar"
        }
    }

    /// Icon background. Nil draws a neutral gray icon.
    public var tint: RainbowTint? {
        switch self {
        case .clock, .settings, .mirror: nil
        case .timers, .alarms, .home: .orange
        case .music, .recipes: .red
        case .weather, .beam, .projectedApps: .blue
        case .photos: .yellow
        case .people, .pairing: .purple
        case .intercom: .yellow
        case .calendar: .red
        }
    }
}

public enum HubWidgetKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case clock, calendar, weather, timers, nextAlarm, nowPlaying, home, thermostat, camera, photo

    public var id: String { rawValue }

    public var access: ContentAccess {
        switch self {
        case .clock, .calendar, .weather, .timers, .nowPlaying, .home, .thermostat, .camera, .photo: .guest
        case .nextAlarm: .member
        }
    }

    public var requiresPersonalContent: Bool { access == .personal }

    /// The app a tap on the widget opens.
    public var app: HubApp {
        switch self {
        case .clock, .calendar: .clock
        case .weather: .weather
        case .timers: .timers
        case .nextAlarm: .alarms
        case .nowPlaying: .music
        case .home, .thermostat, .camera: .home
        case .photo: .photos
        }
    }
}

/// Who is in front of the hub, reduced to what visibility depends on.
public struct AudienceContext: Equatable, Sendable {
    public let isGuest: Bool
    public let isPersonalContentUnlocked: Bool
    public let setupMode: Bool

    public init(isGuest: Bool, isPersonalContentUnlocked: Bool, setupMode: Bool) {
        self.isGuest = isGuest
        self.isPersonalContentUnlocked = isPersonalContentUnlocked
        self.setupMode = setupMode
    }
}

public enum ContentVisibility: Equatable, Sendable {
    case visible
    /// Present but greyed out, with no personal detail.
    case redacted
    case hidden
}

public enum TapAction: Equatable, Sendable {
    case open
    /// Run the device's biometrics, then open what was tapped if that unlocked it.
    case requestUnlock
    case none
}

public enum VisibilityPolicy {
    public static func visibility(for access: ContentAccess, context: AudienceContext) -> ContentVisibility {
        switch access {
        case .guest:
            return .visible
        case .member:
            return context.isGuest ? .hidden : .visible
        case .personal:
            if context.isGuest { return .hidden }
            return context.isPersonalContentUnlocked ? .visible : .redacted
        case .setup:
            return context.setupMode ? .visible : .hidden
        }
    }

    public static func visibility(of app: HubApp, context: AudienceContext) -> ContentVisibility {
        visibility(for: app.access, context: context)
    }

    public static func visibility(of widget: HubWidgetKind, context: AudienceContext) -> ContentVisibility {
        visibility(for: widget.access, context: context)
    }

    /// Whether an app has an icon at all. An optional app is listed only while the package
    /// behind it is supplying it.
    public static func isListed(_ app: HubApp, available: Set<HubApp>) -> Bool {
        !app.isOptional || available.contains(app)
    }

    /// Only a fully visible app opens. A redacted icon stays put so nothing personal is revealed.
    public static func canOpen(_ app: HubApp, context: AudienceContext) -> Bool {
        visibility(of: app, context: context) == .visible
    }

    /// What a tap on an app icon or a widget does. A greyed-out personal item is normally inert.
    /// While the device's own biometrics are offered, the tap asks to unlock instead.
    public static func tapAction(for access: ContentAccess, context: AudienceContext, isDeviceUnlockOffered: Bool) -> TapAction {
        switch visibility(for: access, context: context) {
        case .visible: .open
        case .redacted: isDeviceUnlockOffered ? .requestUnlock : .none
        case .hidden: .none
        }
    }

    /// After an unlock attempt, the app the person tapped opens only when the attempt worked
    /// and the app is now theirs to see.
    public static func appToOpen(afterUnlock succeeded: Bool, requested: HubApp?, context: AudienceContext) -> HubApp? {
        guard succeeded, let requested, canOpen(requested, context: context) else { return nil }
        return requested
    }

    /// Whether to show "Unlock with Touch ID": someone is personalized but locked, and the
    /// device can confirm them.
    public static func showsDeviceUnlock(context: AudienceContext, isDeviceUnlockOffered: Bool) -> Bool {
        isDeviceUnlockOffered && !context.isGuest && !context.isPersonalContentUnlocked
    }

    /// With setup mode off and nobody enrolled there is no way to add people from inside the app,
    /// so the shell points at Settings.
    public static func needsSetupHint(profileCount: Int, setupMode: Bool) -> Bool {
        profileCount == 0 && !setupMode
    }
}
