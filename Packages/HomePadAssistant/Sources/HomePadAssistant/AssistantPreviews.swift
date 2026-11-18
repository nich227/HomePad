#if DEBUG
import HomePadAssistantCore
import SwiftUI

/// A hub that exists only in previews: it accepts every action and offers a little context.
@MainActor
private final class PreviewHub: AssistantActions, AssistantHubContext {
    let owner = UUID()
    var hubState = AssistantHubState(hubName: "Kitchen", screenTitle: "Clock face", usesFahrenheit: true)

    func contextItems() async -> [AssistantContextItem] {
        [
            AssistantContextItem(id: "weather", kind: .weather, title: "Sunny", detail: "68 degrees, high of 72"),
            AssistantContextItem(id: "event", kind: .calendarEvent, ownerID: owner, title: "Dentist", detail: "Tomorrow at 9:00 AM"),
        ]
    }

    private func timer(_ name: String?, _ remaining: TimeInterval) -> AssistantTimer {
        AssistantTimer(id: UUID(), name: name ?? "Timer", remaining: remaining)
    }

    func startTimer(name: String?, duration: TimeInterval) async -> Result<AssistantTimer, AssistantActionError> {
        .success(timer(name, duration))
    }

    func pauseTimer(name: String?) async -> Result<AssistantTimer, AssistantActionError> {
        .success(timer(name, 120))
    }

    func cancelTimer(name: String?) async -> Result<AssistantTimer, AssistantActionError> {
        .success(timer(name, 0))
    }

    func timers() async -> Result<[AssistantTimer], AssistantActionError> {
        .success([timer("Pasta", 540)])
    }

    func show(named name: String) async -> Result<AssistantDestination, AssistantActionError> {
        .success(.app(name))
    }

    func setNightMode(_ isOn: Bool) async -> Result<Bool, AssistantActionError> {
        .success(isOn)
    }

    func runScene(named name: String) async -> Result<String, AssistantActionError> {
        .success(name)
    }

    func setThermostat(targetCelsius: Double) async -> Result<AssistantThermostat, AssistantActionError> {
        .success(AssistantThermostat(name: "Hallway", targetCelsius: targetCelsius))
    }

    func setAccessory(named name: String, isOn: Bool) async -> Result<AssistantAccessory, AssistantActionError> {
        .success(AssistantAccessory(name: name, isOn: isOn))
    }

    func weatherSummary() async -> Result<String, AssistantActionError> {
        .success("Sunny and 68 degrees, with a high of 72.")
    }

    func openWebPage(_ url: URL) async -> Result<URL, AssistantActionError> {
        .success(url)
    }

    func sendHouseholdNote(_ text: String) async -> Result<AssistantNoteReceipt, AssistantActionError> {
        .success(AssistantNoteReceipt(recipientCount: 2))
    }

    func screenSummary() async -> Result<String, AssistantActionError> {
        .success("The clock face, showing five past two.")
    }
}

/// Opens the overlay over a stand-in for the hub and asks one question, so the card shows an
/// answer, a snippet, and follow-up chips without a model.
private struct OverlayPreview: View {
    let isNight: Bool
    @State private var hub = PreviewHub()
    @State private var engine: AssistantEngine?
    @State private var isShowing = true

    var body: some View {
        ZStack {
            (isNight ? Color.black : Color(red: 0.10, green: 0.16, blue: 0.30)).ignoresSafeArea()
            Text("2:05")
                .font(.system(size: 160, weight: .semibold, design: .rounded))
                .foregroundStyle(isNight ? Color(AssistantColor.nightRed) : .white)
            if let engine, isShowing {
                AssistantOverlayView(engine: engine, isNight: isNight) {
                    isShowing = false
                }
            } else {
                Button("Open Assistant") { isShowing = true }
                    .buttonStyle(.glass)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding()
            }
        }
        .task {
            let audience = AssistantAudience(memberID: hub.owner, memberName: "Erica", isRecognized: true, isPersonalContentUnlocked: true)
            let engine = AssistantEngine.scripted(actions: hub, hub: hub, audience: audience)
            self.engine = engine
            engine.open()
            engine.submit("What is my day like?")
        }
    }
}

#Preview("Overlay") {
    OverlayPreview(isNight: false)
}

#Preview("Overlay, Night Mode") {
    OverlayPreview(isNight: true)
}

#Preview("Gate: turn it on") {
    AppleIntelligenceRequiredView(gate: AppleIntelligenceGate(hooks: .none, read: { .unavailable(.appleIntelligenceNotEnabled) }))
}

#Preview("Gate: not supported") {
    AppleIntelligenceRequiredView(gate: AppleIntelligenceGate(hooks: .none, read: { .unavailable(.deviceNotEligible) }))
}

#Preview("Gate: getting ready") {
    AppleIntelligenceRequiredView(gate: AppleIntelligenceGate(hooks: .none, read: { .unavailable(.modelNotReady) }))
}
#endif
