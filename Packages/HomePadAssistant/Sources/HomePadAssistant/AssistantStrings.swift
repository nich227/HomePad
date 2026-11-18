import Foundation
import HomePadAssistantCore
import SwiftUI

extension Color {
    init(_ color: AssistantColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.opacity)
    }
}

extension AssistantFailure {
    /// What the card shows when a request ends without an answer.
    var message: String {
        switch self {
        case .noSpeech:
            String(localized: "I did not hear anything. Tap the microphone to try again, or type.")
        case .speechUnavailable:
            String(localized: "This device cannot recognize speech on its own in this language. Type your request instead.")
        case .speechNotPermitted:
            String(localized: "Speech Recognition is turned off for HomePad. Turn it on in Settings, or type your request.")
        case .microphoneNotPermitted:
            String(localized: "The microphone is turned off for HomePad. Turn it on in Settings, or type your request.")
        case .interrupted:
            String(localized: "Something else is using the microphone. Try again in a moment.")
        case .modelUnavailable:
            String(localized: "Apple Intelligence is not available right now.")
        case .contextTooLong:
            String(localized: "That was too much to keep in mind. Ask again in fewer words.")
        case .refused:
            String(localized: "I cannot help with that.")
        case .unsupportedLanguage:
            String(localized: "I cannot answer in this language yet.")
        case .busy:
            String(localized: "I am still working on something else. Try again in a moment.")
        case .timedOut:
            String(localized: "That took too long. Try again.")
        case .unknown:
            String(localized: "Something went wrong. Try again.")
        }
    }
}

extension AssistantFollowUp {
    /// The chip's label. Tapping the chip sends the same words as a request.
    var title: String {
        switch self {
        case .pauseTimer(let name): String(localized: "Pause the \(name) timer")
        case .cancelTimer(let name): String(localized: "Cancel the \(name) timer")
        case .showTimers: String(localized: "Show my timers")
        case .nightMode(isOn: true): String(localized: "Turn on Night Mode")
        case .nightMode(isOn: false): String(localized: "Turn off Night Mode")
        case .accessory(let name, isOn: true): String(localized: "Turn on \(name)")
        case .accessory(let name, isOn: false): String(localized: "Turn off \(name)")
        case .suggested(let text): text
        }
    }
}

extension AssistantContextItem.Kind {
    var symbolName: String {
        switch self {
        case .timer: "timer"
        case .weather: "cloud.sun.fill"
        case .home: "house.fill"
        case .nowPlaying: "music.note"
        case .playlist: "music.note.list"
        case .calendarEvent: "calendar"
        case .message: "message.fill"
        case .reminder: "checklist"
        }
    }
}

extension AssistantActionReport {
    /// The outcome in the person's language, for an App Intent's dialog and for the card when
    /// the model did something and said nothing.
    public var dialogText: String {
        switch result {
        case .success(let value): Self.dialog(for: value)
        case .failure(let error): Self.dialog(for: error)
        }
    }

    private static func length(_ interval: TimeInterval) -> String {
        Duration.seconds(interval.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    private static func dialog(for value: AssistantActionValue) -> String {
        switch value {
        case .timerStarted(let timer):
            return String(localized: "The \(timer.name) timer is set for \(length(timer.remaining)).")
        case .timerPaused(let timer):
            return String(localized: "The \(timer.name) timer is paused with \(length(timer.remaining)) left.")
        case .timerCanceled(let timer):
            return String(localized: "The \(timer.name) timer is canceled.")
        case .timers(let timers):
            guard !timers.isEmpty else { return String(localized: "No timers are set.") }
            return timers.map { timer in
                timer.isPaused
                    ? String(localized: "\(timer.name): \(length(timer.remaining)) left, paused.")
                    : String(localized: "\(timer.name): \(length(timer.remaining)) left.")
            }.joined(separator: " ")
        case .showing(let destination):
            return String(localized: "Showing \(destination.name).")
        case .nightMode(true):
            return String(localized: "Night Mode is on.")
        case .nightMode(false):
            return String(localized: "Night Mode is off.")
        case .sceneRan(let name):
            return String(localized: "\(name) is set.")
        case .thermostat(let thermostat):
            let target = Measurement(value: thermostat.targetCelsius, unit: UnitTemperature.celsius)
                .formatted(.measurement(width: .abbreviated, usage: .weather))
            return String(localized: "\(thermostat.name) is set to \(target).")
        case .accessory(let accessory):
            return accessory.isOn
                ? String(localized: "\(accessory.name) is on.")
                : String(localized: "\(accessory.name) is off.")
        case .weather(let summary), .screen(let summary):
            return summary
        case .pageOpened:
            return String(localized: "The page is open on HomePad.")
        case .noteSent:
            return String(localized: "The note is sent.")
        }
    }

    private static func dialog(for error: AssistantActionError) -> String {
        switch error {
        case .needsHouseholdMember:
            String(localized: "That needs a member of the household. Choose your profile on HomePad first.")
        case .needsRecognizedMember:
            String(localized: "That needs a household member HomePad recognizes. Step in front of HomePad and try again.")
        case .personalContentLocked:
            String(localized: "That is personal and stays locked until HomePad recognizes its owner.")
        case .notFound(let name):
            String(localized: "HomePad has nothing named \(name).")
        case .unavailable:
            String(localized: "HomePad cannot do that right now. Open HomePad and try again.")
        case .invalid(.emptyName):
            String(localized: "A name is needed.")
        case .invalid(.durationOutOfRange):
            String(localized: "A timer can run from one second to 24 hours.")
        case .invalid(.temperatureOutOfRange):
            String(localized: "That temperature is outside what the thermostat accepts.")
        case .invalid(.notAWebPage):
            String(localized: "Only web pages that start with http or https can be opened on HomePad.")
        case .invalid(.emptyNote):
            String(localized: "The note is empty.")
        case .limitReached:
            String(localized: "That was too many things at once. Ask for fewer.")
        }
    }
}
