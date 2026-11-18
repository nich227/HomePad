import Foundation
import FoundationModels
import HomePadAssistantCore

/// The model's tools. Each one turns its arguments into an `AssistantRequest` and hands it to
/// the toolbox, which checks who is asking before anything happens. The text a tool returns is
/// a plain fact for the model to word an answer from.
enum AssistantTools {
    /// The tools for what this audience may do. A tool the audience may not use is left out, so
    /// the model does not try it, and the toolbox would refuse it anyway.
    @MainActor
    static func tools(for capabilities: [AssistantCapability], toolbox: AssistantToolbox) -> [any Tool] {
        var tools: [any Tool] = [HubInfoTool(toolbox: toolbox)]
        for capability in capabilities {
            switch capability {
            case .timers: tools.append(TimerTool(toolbox: toolbox))
            case .navigation: tools.append(ShowTool(toolbox: toolbox))
            case .nightMode: tools.append(NightModeTool(toolbox: toolbox))
            case .accessories: tools.append(AccessoryTool(toolbox: toolbox))
            case .climate: tools.append(ThermostatTool(toolbox: toolbox))
            case .browser: tools.append(WebPageTool(toolbox: toolbox))
            case .notes: tools.append(NoteTool(toolbox: toolbox))
            case .scenes: tools.append(SceneTool(toolbox: toolbox))
            case .weather, .screen: break
            }
        }
        return tools
    }
}

@Generable
enum HubInfoTopic {
    case timers
    case weather
    case screen
}

struct HubInfoTool: Tool {
    let toolbox: AssistantToolbox
    let name = "hubInfo"
    let description = "Looks up the timers that are set, the weather, or what the hub's screen shows."

    @Generable
    struct Arguments {
        @Guide(description: "What to look up.")
        var topic: HubInfoTopic
    }

    func call(arguments: Arguments) async throws -> String {
        let request: AssistantRequest = switch arguments.topic {
        case .timers: .listTimers
        case .weather: .weather
        case .screen: .readScreen
        }
        return await toolbox.perform(request).modelText
    }
}

@Generable
enum TimerAction {
    case start
    case pause
    case cancel
}

struct TimerTool: Tool {
    let toolbox: AssistantToolbox
    let name = "timer"
    let description = "Starts, pauses, or cancels a timer on the hub."

    @Generable
    struct Arguments {
        @Guide(description: "What to do with the timer.")
        var action: TimerAction
        @Guide(description: "The timer's name, such as Pasta. Leave out when no name was given.")
        var name: String?
        @Guide(description: "How long the timer runs, in seconds. Needed to start one.")
        var seconds: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let request: AssistantRequest = switch arguments.action {
        case .start: .startTimer(name: arguments.name, seconds: arguments.seconds ?? 0)
        case .pause: .pauseTimer(name: arguments.name)
        case .cancel: .cancelTimer(name: arguments.name)
        }
        return await toolbox.perform(request).modelText
    }
}

struct ShowTool: Tool {
    let toolbox: AssistantToolbox
    let name = "show"
    let description = "Brings a clock face or an app to the front of the hub, by name."

    @Generable
    struct Arguments {
        @Guide(description: "The name of the face or app, such as Weather or Photos.")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.perform(.show(name: arguments.name)).modelText
    }
}

struct NightModeTool: Tool {
    let toolbox: AssistantToolbox
    let name = "nightMode"
    let description = "Turns the hub's Night Mode on or off."

    @Generable
    struct Arguments {
        @Guide(description: "True turns Night Mode on. False turns it off.")
        var isOn: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.perform(.setNightMode(isOn: arguments.isOn)).modelText
    }
}

struct SceneTool: Tool {
    let toolbox: AssistantToolbox
    let name = "runScene"
    let description = "Runs a home scene, such as Good Night."

    @Generable
    struct Arguments {
        @Guide(description: "The scene's name.")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.perform(.runScene(name: arguments.name)).modelText
    }
}

struct ThermostatTool: Tool {
    let toolbox: AssistantToolbox
    let name = "thermostat"
    let description = "Sets the temperature the thermostat aims for."

    @Generable
    struct Arguments {
        @Guide(description: "The target temperature, in the unit the hub state says temperatures are shown in.")
        var degrees: Double
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.perform(.setThermostat(degrees: arguments.degrees, scale: .hub)).modelText
    }
}

struct AccessoryTool: Tool {
    let toolbox: AssistantToolbox
    let name = "accessory"
    let description = "Turns a home accessory, such as a lamp or a plug, on or off."

    @Generable
    struct Arguments {
        @Guide(description: "The accessory's name.")
        var name: String
        @Guide(description: "True turns it on. False turns it off.")
        var isOn: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.perform(.setAccessory(name: arguments.name, isOn: arguments.isOn)).modelText
    }
}

struct WebPageTool: Tool {
    let toolbox: AssistantToolbox
    let name = "openWebPage"
    let description = "Opens a web page in the hub's browser. Use only an address the person gave."

    @Generable
    struct Arguments {
        @Guide(description: "The full address, starting with https or http.")
        var address: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.perform(.openWebPage(address: arguments.address)).modelText
    }
}

struct NoteTool: Tool {
    let toolbox: AssistantToolbox
    let name = "sendNote"
    let description = "Sends a short note to the household's paired phones."

    @Generable
    struct Arguments {
        @Guide(description: "The note, in the person's own words.")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.perform(.sendNote(text: arguments.text)).modelText
    }
}
