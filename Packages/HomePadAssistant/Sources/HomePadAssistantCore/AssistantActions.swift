import Foundation

public struct AssistantTimer: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let remaining: TimeInterval
    public let isPaused: Bool

    public init(id: UUID, name: String, remaining: TimeInterval, isPaused: Bool = false) {
        self.id = id
        self.name = name
        self.remaining = remaining
        self.isPaused = isPaused
    }
}

/// What came to the front after a request to show something.
public enum AssistantDestination: Equatable, Sendable {
    case face(String)
    case app(String)

    public var name: String {
        switch self {
        case .face(let name), .app(let name): name
        }
    }
}

public struct AssistantThermostat: Equatable, Sendable {
    public let name: String
    public let targetCelsius: Double

    public init(name: String, targetCelsius: Double) {
        self.name = name
        self.targetCelsius = targetCelsius
    }
}

public struct AssistantAccessory: Equatable, Sendable {
    public let name: String
    public let isOn: Bool

    public init(name: String, isOn: Bool) {
        self.name = name
        self.isOn = isOn
    }
}

public struct AssistantNoteReceipt: Equatable, Sendable {
    /// How many paired devices the note went to.
    public let recipientCount: Int

    public init(recipientCount: Int) {
        self.recipientCount = recipientCount
    }
}

public enum AssistantInvalidRequest: Equatable, Sendable {
    case emptyName
    case durationOutOfRange
    case temperatureOutOfRange
    case notAWebPage
    case emptyNote
}

/// Why an action did not happen.
public enum AssistantActionError: Error, Equatable, Sendable {
    /// A guest asked for something that is done in a member's name.
    case needsHouseholdMember
    /// The camera has not recognized a member. A profile picked by hand is not enough.
    case needsRecognizedMember
    /// The thing asked for belongs to one person and their face has not unlocked it.
    case personalContentLocked
    case notFound(String)
    case unavailable
    case invalid(AssistantInvalidRequest)
    /// One request asked for more actions than a single turn may run.
    case limitReached
}

/// What the Assistant can do in the hub. The app implements this over its own models.
///
/// The Assistant checks who is asking before it calls any of these, so an implementation only
/// reports what the hub itself knows: not found, unavailable, or personal and locked.
@MainActor
public protocol AssistantActions: AnyObject {
    /// A nil name lets the hub pick one.
    func startTimer(name: String?, duration: TimeInterval) async -> Result<AssistantTimer, AssistantActionError>
    /// A nil name means the only timer, or the one started last.
    func pauseTimer(name: String?) async -> Result<AssistantTimer, AssistantActionError>
    func cancelTimer(name: String?) async -> Result<AssistantTimer, AssistantActionError>
    func timers() async -> Result<[AssistantTimer], AssistantActionError>
    /// Brings a face or an app to the front by its name.
    func show(named name: String) async -> Result<AssistantDestination, AssistantActionError>
    func setNightMode(_ isOn: Bool) async -> Result<Bool, AssistantActionError>
    /// Returns the name of the scene that ran.
    func runScene(named name: String) async -> Result<String, AssistantActionError>
    func setThermostat(targetCelsius: Double) async -> Result<AssistantThermostat, AssistantActionError>
    func setAccessory(named name: String, isOn: Bool) async -> Result<AssistantAccessory, AssistantActionError>
    func weatherSummary() async -> Result<String, AssistantActionError>
    /// Opens a page in the hub's browser. The address is already known to be http or https.
    func openWebPage(_ url: URL) async -> Result<URL, AssistantActionError>
    func sendHouseholdNote(_ text: String) async -> Result<AssistantNoteReceipt, AssistantActionError>
    /// A short description of what the screen shows right now, with nothing that is hidden
    /// from the person in front of it.
    func screenSummary() async -> Result<String, AssistantActionError>
}

public enum AssistantTemperatureScale: Equatable, Sendable {
    case celsius
    case fahrenheit
    /// Whichever the hub shows.
    case hub
}

/// One thing asked of the hub, as plain values. The model's tools and the App Intents both
/// build one of these and hand it to `AssistantRouter`.
public enum AssistantRequest: Equatable, Sendable {
    case startTimer(name: String?, seconds: Int)
    case pauseTimer(name: String?)
    case cancelTimer(name: String?)
    case listTimers
    case show(name: String)
    case setNightMode(isOn: Bool)
    case runScene(name: String)
    case setThermostat(degrees: Double, scale: AssistantTemperatureScale)
    case setAccessory(name: String, isOn: Bool)
    case weather
    case openWebPage(address: String)
    case sendNote(text: String)
    case readScreen

    public var capability: AssistantCapability {
        switch self {
        case .startTimer, .pauseTimer, .cancelTimer, .listTimers: .timers
        case .show: .navigation
        case .setNightMode: .nightMode
        case .runScene: .scenes
        case .setThermostat: .climate
        case .setAccessory: .accessories
        case .weather: .weather
        case .openWebPage: .browser
        case .sendNote: .notes
        case .readScreen: .screen
        }
    }
}

public enum AssistantActionValue: Equatable, Sendable {
    case timerStarted(AssistantTimer)
    case timerPaused(AssistantTimer)
    case timerCanceled(AssistantTimer)
    case timers([AssistantTimer])
    case showing(AssistantDestination)
    case nightMode(Bool)
    case sceneRan(String)
    case thermostat(AssistantThermostat)
    case accessory(AssistantAccessory)
    case weather(String)
    case pageOpened(URL)
    case noteSent(AssistantNoteReceipt)
    case screen(String)
}

/// What happened to one request.
public struct AssistantActionReport: Equatable, Sendable {
    public let request: AssistantRequest
    public let result: Result<AssistantActionValue, AssistantActionError>

    public init(request: AssistantRequest, result: Result<AssistantActionValue, AssistantActionError>) {
        self.request = request
        self.result = result
    }

    public var value: AssistantActionValue? {
        try? result.get()
    }

    /// The outcome as a plain English fact for the model. It is data for the model to word an
    /// answer from, not text for the screen.
    public var modelText: String {
        switch result {
        case .success(let value): Self.text(for: value)
        case .failure(let error): "Not done. " + Self.text(for: error)
        }
    }

    static func text(for value: AssistantActionValue) -> String {
        switch value {
        case .timerStarted(let timer):
            return "Timer \(timer.name) started for \(AssistantText.duration(timer.remaining))."
        case .timerPaused(let timer):
            return "Timer \(timer.name) paused with \(AssistantText.duration(timer.remaining)) left."
        case .timerCanceled(let timer):
            return "Timer \(timer.name) canceled."
        case .timers(let timers):
            guard !timers.isEmpty else { return "No timers are set." }
            let lines = timers.map { timer in
                "\(timer.name), \(AssistantText.duration(timer.remaining)) left" + (timer.isPaused ? " (paused)" : "")
            }
            return "Timers: " + lines.joined(separator: "; ") + "."
        case .showing(.face(let name)):
            return "Showing the \(name) face."
        case .showing(.app(let name)):
            return "Opened \(name)."
        case .nightMode(let isOn):
            return "Night Mode is \(isOn ? "on" : "off")."
        case .sceneRan(let name):
            return "Scene \(name) ran."
        case .thermostat(let thermostat):
            let celsius = thermostat.targetCelsius
            let fahrenheit = celsius * 9 / 5 + 32
            return "\(thermostat.name) set to \(AssistantText.degrees(celsius)) Celsius, which is \(AssistantText.degrees(fahrenheit)) Fahrenheit."
        case .accessory(let accessory):
            return "\(accessory.name) is \(accessory.isOn ? "on" : "off")."
        case .weather(let summary):
            return "Weather: \(summary)"
        case .pageOpened(let url):
            return "Opened the page from \(url.host() ?? "the web") in the hub's browser."
        case .noteSent(let receipt):
            return "Note sent to \(receipt.recipientCount) paired \(receipt.recipientCount == 1 ? "device" : "devices")."
        case .screen(let summary):
            return "On screen: \(summary)"
        }
    }

    static func text(for error: AssistantActionError) -> String {
        switch error {
        case .needsHouseholdMember:
            "The person is a guest and this needs a household member."
        case .needsRecognizedMember:
            "This needs a household member the hub's camera has recognized."
        case .personalContentLocked:
            "This is personal and stays locked until its owner is recognized."
        case .notFound(let name):
            "Nothing named \(name) was found."
        case .unavailable:
            "This is not available right now."
        case .invalid(.emptyName):
            "A name is needed."
        case .invalid(.durationOutOfRange):
            "A timer runs between one second and 24 hours."
        case .invalid(.temperatureOutOfRange):
            "The temperature is outside what a thermostat accepts."
        case .invalid(.notAWebPage):
            "Only web addresses that start with http or https can be opened."
        case .invalid(.emptyNote):
            "The note is empty."
        case .limitReached:
            "Too many actions for one request."
        }
    }
}

/// Checks who is asking and what they asked for, then calls the hub. Every path to
/// `AssistantActions` goes through here, so the rules hold for the model and for App Intents alike.
@MainActor
public final class AssistantRouter {
    private let actions: any AssistantActions
    private let audience: @MainActor () -> AssistantAudience
    private let usesFahrenheit: @MainActor () -> Bool

    public init(
        actions: any AssistantActions,
        audience: @escaping @MainActor () -> AssistantAudience,
        usesFahrenheit: @escaping @MainActor () -> Bool
    ) {
        self.actions = actions
        self.audience = audience
        self.usesFahrenheit = usesFahrenheit
    }

    public func perform(_ request: AssistantRequest) async -> AssistantActionReport {
        AssistantActionReport(request: request, result: await result(of: request))
    }

    private func result(of request: AssistantRequest) async -> Result<AssistantActionValue, AssistantActionError> {
        if let denial = AssistantPolicy.denial(for: request.capability, audience: audience()) {
            return .failure(denial)
        }
        switch request {
        case .startTimer(let name, let seconds):
            guard AssistantLimits.timerSecondsRange.contains(seconds) else {
                return .failure(.invalid(.durationOutOfRange))
            }
            return await actions.startTimer(name: Self.optionalName(name), duration: TimeInterval(seconds)).map(AssistantActionValue.timerStarted)
        case .pauseTimer(let name):
            return await actions.pauseTimer(name: Self.optionalName(name)).map(AssistantActionValue.timerPaused)
        case .cancelTimer(let name):
            return await actions.cancelTimer(name: Self.optionalName(name)).map(AssistantActionValue.timerCanceled)
        case .listTimers:
            return await actions.timers().map(AssistantActionValue.timers)
        case .show(let name):
            guard let name = Self.optionalName(name) else { return .failure(.invalid(.emptyName)) }
            return await actions.show(named: name).map(AssistantActionValue.showing)
        case .setNightMode(let isOn):
            return await actions.setNightMode(isOn).map(AssistantActionValue.nightMode)
        case .runScene(let name):
            guard let name = Self.optionalName(name) else { return .failure(.invalid(.emptyName)) }
            return await actions.runScene(named: name).map(AssistantActionValue.sceneRan)
        case .setThermostat(let degrees, let scale):
            let celsius = Self.celsius(degrees, scale: scale, hubUsesFahrenheit: usesFahrenheit())
            guard AssistantLimits.thermostatCelsiusRange.contains(celsius) else {
                return .failure(.invalid(.temperatureOutOfRange))
            }
            return await actions.setThermostat(targetCelsius: celsius).map(AssistantActionValue.thermostat)
        case .setAccessory(let name, let isOn):
            guard let name = Self.optionalName(name) else { return .failure(.invalid(.emptyName)) }
            return await actions.setAccessory(named: name, isOn: isOn).map(AssistantActionValue.accessory)
        case .weather:
            return await actions.weatherSummary().map { .weather(AssistantText.singleLine($0, limit: AssistantLimits.maxToolTextCharacters)) }
        case .openWebPage(let address):
            guard let url = Self.webPage(address) else { return .failure(.invalid(.notAWebPage)) }
            return await actions.openWebPage(url).map(AssistantActionValue.pageOpened)
        case .sendNote(let text):
            let note = AssistantText.singleLine(text, limit: AssistantLimits.maxNoteCharacters)
            guard !note.isEmpty else { return .failure(.invalid(.emptyNote)) }
            return await actions.sendHouseholdNote(note).map(AssistantActionValue.noteSent)
        case .readScreen:
            return await actions.screenSummary().map { .screen(AssistantText.singleLine($0, limit: AssistantLimits.maxToolTextCharacters)) }
        }
    }

    static func optionalName(_ name: String?) -> String? {
        let cleaned = AssistantText.singleLine(name ?? "", limit: AssistantLimits.maxNameCharacters)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Rounded to half a degree, which is as fine as a thermostat goes.
    static func celsius(_ degrees: Double, scale: AssistantTemperatureScale, hubUsesFahrenheit: Bool) -> Double {
        let isFahrenheit = scale == .fahrenheit || (scale == .hub && hubUsesFahrenheit)
        let celsius = isFahrenheit ? (degrees - 32) * 5 / 9 : degrees
        return (celsius * 2).rounded() / 2
    }

    /// A page the hub's browser may open: http or https with a host, and nothing else.
    static func webPage(_ address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= AssistantLimits.maxAddressCharacters,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil
        else { return nil }
        return components.url
    }
}
