import AppIntents
import Foundation
import HomePadAssistantCore

/// Where the Assistant's App Intents find the running app. The app fills this in while it
/// launches, before any scene exists, because Siri and Shortcuts start the app in the
/// background to run an intent.
@MainActor
public final class AssistantIntentHandlers {
    public static let shared = AssistantIntentHandlers()

    /// Performs one request on the hub. Set to `AssistantEngine.perform(_:)`, which applies the
    /// same rules as the Assistant: who is in front of the hub decides what is allowed.
    public var perform: (@MainActor (AssistantRequest) async -> AssistantActionReport)?

    private init() {}

    public func register(engine: AssistantEngine) {
        perform = { [weak engine] request in
            await engine?.perform(request) ?? AssistantActionReport(request: request, result: .failure(.unavailable))
        }
    }

    func run(_ request: AssistantRequest) async -> AssistantActionReport {
        await perform?(request) ?? AssistantActionReport(request: request, result: .failure(.unavailable))
    }
}

/// Makes this package's intents visible to the app. The app target lists it in the
/// `includedPackages` of its own `AppIntentsPackage`.
public struct HomePadAssistantIntents: AppIntentsPackage {}

private func intentResult(_ report: AssistantActionReport) -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
    .result(value: report.value != nil, dialog: IntentDialog(stringLiteral: report.dialogText))
}

// MARK: Timers

public struct StartHubTimerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Timer on HomePad"
    public static let description = IntentDescription("Starts a timer on this HomePad.", categoryName: "Timers")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Duration", description: "How long the timer runs.", defaultUnit: .minutes, supportsNegativeNumbers: false)
    public var duration: Measurement<UnitDuration>

    @Parameter(title: "Name", description: "What the timer is for. Optional.")
    public var name: String?

    public static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$duration) timer on HomePad") {
            \.$name
        }
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let seconds = Int(duration.converted(to: .seconds).value.rounded())
        return intentResult(await AssistantIntentHandlers.shared.run(.startTimer(name: name, seconds: seconds)))
    }
}

public struct CancelHubTimerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Cancel Timer on HomePad"
    public static let description = IntentDescription("Cancels a timer on this HomePad. Without a name, cancels the only timer or the one started last.", categoryName: "Timers")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Name", description: "Which timer to cancel. Optional.")
    public var name: String?

    public static var parameterSummary: some ParameterSummary {
        Summary("Cancel the \(\.$name) timer on HomePad")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        intentResult(await AssistantIntentHandlers.shared.run(.cancelTimer(name: name)))
    }
}

// MARK: Faces, apps, and Night Mode

public struct ShowOnHubIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Face or App on HomePad"
    public static let description = IntentDescription("Brings a clock face or an app to the front on this HomePad, by its name.", categoryName: "Hub")
    public static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Name", description: "The name of the face or app, such as Weather.")
    public var name: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$name) on HomePad")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        intentResult(await AssistantIntentHandlers.shared.run(.show(name: name)))
    }
}

public enum HubSwitchState: String, AppEnum {
    case on
    case off

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "On or Off"
    public static let caseDisplayRepresentations: [HubSwitchState: DisplayRepresentation] = [
        .on: "On",
        .off: "Off",
    ]
}

public struct SetHubNightModeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Night Mode on HomePad"
    public static let description = IntentDescription("Turns Night Mode on or off on this HomePad.", categoryName: "Hub")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Night Mode", default: .on)
    public var state: HubSwitchState

    public static var parameterSummary: some ParameterSummary {
        Summary("Turn Night Mode \(\.$state) on HomePad")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        intentResult(await AssistantIntentHandlers.shared.run(.setNightMode(isOn: state == .on)))
    }
}

// MARK: Home

public struct RunHubSceneIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Scene on HomePad"
    public static let description = IntentDescription(
        "Runs a home scene from this HomePad. HomePad runs scenes only while it recognizes a household member in front of it.",
        categoryName: "Home"
    )
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Scene", description: "The scene's name, such as Good Night.")
    public var scene: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$scene) on HomePad")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        intentResult(await AssistantIntentHandlers.shared.run(.runScene(name: scene)))
    }
}

public struct SetHubThermostatIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Thermostat on HomePad"
    public static let description = IntentDescription("Sets the temperature the thermostat aims for, from this HomePad.", categoryName: "Home")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Temperature")
    public var temperature: Measurement<UnitTemperature>

    public static var parameterSummary: some ParameterSummary {
        Summary("Set the thermostat to \(\.$temperature) on HomePad")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let celsius = temperature.converted(to: .celsius).value
        return intentResult(await AssistantIntentHandlers.shared.run(.setThermostat(degrees: celsius, scale: .celsius)))
    }
}
