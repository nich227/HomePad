import Foundation
import Observation

/// A preference the user changes in the system Settings app. The app reads it and never writes it.
public struct SettingKey<Value: Sendable & Equatable>: Sendable, Equatable {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

/// Describes one row of the Settings bundle. Each package lists its descriptors so the bundle's
/// plists can be checked against the keys the code reads.
public struct SettingDescriptor: Sendable, Equatable {
    public enum Default: Sendable, Equatable {
        case bool(Bool)
        case string(String)
        case integer(Int)
        case number(Double)

        var propertyListValue: Any {
            switch self {
            case .bool(let value): value
            case .string(let value): value
            case .integer(let value): value
            case .number(let value): value
            }
        }
    }

    public struct Option: Sendable, Equatable {
        public let title: String
        public let value: String

        public init(title: String, value: String) {
            self.title = title
            self.value = value
        }
    }

    public enum Control: Sendable, Equatable {
        case toggle
        case choice([Option])
        case text
        case slider(minimum: Double, maximum: Double)
    }

    public let name: String
    public let title: String
    /// Settings pane the row belongs to, for example "Faces" or "Beam".
    public let pane: String
    public let control: Control
    public let defaultValue: Default
    /// Footer text shown under the row's group.
    public let footer: String?

    public init(name: String, title: String, pane: String, control: Control, defaultValue: Default, footer: String? = nil) {
        self.name = name
        self.title = title
        self.pane = pane
        self.control = control
        self.defaultValue = defaultValue
        self.footer = footer
    }

    public init(_ key: SettingKey<Bool>, title: String, pane: String, footer: String? = nil) {
        self.init(name: key.name, title: title, pane: pane, control: .toggle, defaultValue: .bool(key.defaultValue), footer: footer)
    }

    public init(_ key: SettingKey<String>, title: String, pane: String, options: [Option], footer: String? = nil) {
        self.init(name: key.name, title: title, pane: pane, control: .choice(options), defaultValue: .string(key.defaultValue), footer: footer)
    }

    public init(_ key: SettingKey<String>, title: String, pane: String, footer: String? = nil) {
        self.init(name: key.name, title: title, pane: pane, control: .text, defaultValue: .string(key.defaultValue), footer: footer)
    }

    public init(_ key: SettingKey<Int>, title: String, pane: String, options: [Option], footer: String? = nil) {
        self.init(name: key.name, title: title, pane: pane, control: .choice(options), defaultValue: .integer(key.defaultValue), footer: footer)
    }

    public init(_ key: SettingKey<Double>, title: String, pane: String, minimum: Double, maximum: Double, footer: String? = nil) {
        self.init(name: key.name, title: title, pane: pane, control: .slider(minimum: minimum, maximum: maximum), defaultValue: .number(key.defaultValue), footer: footer)
    }
}

/// Reads preferences that live in the system Settings app. Views that read a value through this
/// type update when the user changes it in Settings and returns to the app.
@MainActor
@Observable
public final class HomePadSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored nonisolated(unsafe) private var observer: (any NSObjectProtocol)?
    private var revision = 0

    public init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        observer = notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    /// Settings only writes a value once the user touches its row, so defaults must be registered
    /// at launch for every descriptor.
    public func register(_ descriptors: [SettingDescriptor]) {
        var values: [String: Any] = [:]
        for descriptor in descriptors {
            values[descriptor.name] = descriptor.defaultValue.propertyListValue
        }
        defaults.register(defaults: values)
        refresh()
    }

    /// Call when the scene becomes active, in case a change was made while the app was suspended.
    public func refresh() {
        revision &+= 1
    }

    public subscript(key: SettingKey<Bool>) -> Bool {
        _ = revision
        return defaults.object(forKey: key.name) as? Bool ?? key.defaultValue
    }

    public subscript(key: SettingKey<String>) -> String {
        _ = revision
        return defaults.string(forKey: key.name) ?? key.defaultValue
    }

    public subscript(key: SettingKey<Int>) -> Int {
        _ = revision
        return defaults.object(forKey: key.name) as? Int ?? key.defaultValue
    }

    public subscript(key: SettingKey<Double>) -> Double {
        _ = revision
        return defaults.object(forKey: key.name) as? Double ?? key.defaultValue
    }
}

/// Preferences that are not owned by one feature package.
public enum GeneralSettings {
    public static let pane = "General"

    /// Setup tasks that need the camera or a second device (adding people, enrolling a face,
    /// pairing an iPhone) are reachable in the app only while this is on.
    public static let setupMode = SettingKey<Bool>("general.setupMode", default: true)
    /// "automatic" follows the device: iPad is the hub, iPhone is a companion.
    public static let deviceRole = SettingKey<String>("general.deviceRole", default: "automatic")
    public static let requireCompanionForPersonalContent = SettingKey<Bool>("general.requireCompanion", default: false)
    /// Seconds the audience stays signed in after the camera loses sight of them. Zero is off.
    public static let staySignedInSeconds = SettingKey<Int>("general.staySignedInSeconds", default: 120)

    public static let staySignedInOptions = [0, 30, 120, 300, 600]

    public static let descriptors: [SettingDescriptor] = [
        SettingDescriptor(
            setupMode,
            title: "Setup Mode",
            pane: pane,
            footer: "While on, HomePad shows People and Pairing so you can add household members, enroll faces, and pair iPhones. Turn it off when you are done."
        ),
        SettingDescriptor(
            deviceRole,
            title: "This Device Is",
            pane: pane,
            options: [
                .init(title: "Automatic", value: "automatic"),
                .init(title: "Hub (shared screen)", value: "hub"),
                .init(title: "Companion (personal device)", value: "companion"),
            ]
        ),
        SettingDescriptor(
            requireCompanionForPersonalContent,
            title: "Personal Content Needs Paired iPhone Nearby",
            pane: pane,
            footer: "When on, a recognized face shows personal content only while that person's paired iPhone is connected."
        ),
        SettingDescriptor(
            staySignedInSeconds,
            title: "Stay Signed In After Stepping Away",
            pane: pane,
            options: [
                .init(title: "Off", value: "0"),
                .init(title: "30 seconds", value: "30"),
                .init(title: "2 minutes", value: "120"),
                .init(title: "5 minutes", value: "300"),
                .init(title: "10 minutes", value: "600"),
            ],
            footer: "How long the hub keeps what you have open, such as pages sent from your iPhone, after it loses sight of you. Come back within this time and everything is where you left it. After it, the hub signs you out and closes them. Personal content such as messages still locks as soon as the hub loses sight of you, and the wait ends at once if the hub sees someone else or is locked. Off signs you out as soon as the hub loses sight of you."
        ),
    ]

    /// The value for `HouseholdSession.lingerDuration`. A stored value that is not one of the
    /// choices falls back to the default.
    public static func lingerDuration(setting: Int) -> TimeInterval {
        TimeInterval(staySignedInOptions.contains(setting) ? setting : staySignedInSeconds.defaultValue)
    }

    public static func resolvedRole(setting: String, isPad: Bool) -> DeviceRole {
        switch setting {
        case "hub": .hub
        case "companion": .companion
        default: isPad ? .hub : .companion
        }
    }
}
