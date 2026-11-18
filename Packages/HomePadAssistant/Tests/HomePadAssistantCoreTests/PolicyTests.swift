import Foundation
import HomePadCore
import Testing
@testable import HomePadAssistantCore

@Suite struct AudienceTests {
    @Test func init_whenGuest_thenNeverRecognizedOrUnlockedWhateverIsPassed() {
        let audience = AssistantAudience(memberID: nil, memberName: "Ghost", isRecognized: true, isPersonalContentUnlocked: true)
        #expect(audience == .guest)
        #expect(audience.isGuest)
        #expect(audience.memberName == nil)
    }

    @Test func init_whenNotRecognized_thenPersonalContentStaysLocked() {
        let audience = AssistantAudience(memberID: Fixtures.erica, memberName: "Erica", isRecognized: false, isPersonalContentUnlocked: true)
        #expect(!audience.isPersonalContentUnlocked)
        #expect(!audience.isGuest)
        #expect(Fixtures.unlockedErica.isPersonalContentUnlocked)
    }

    @MainActor
    @Test func init_whenBuiltFromTheSession_thenFollowsWhoIsInFrontOfTheHub() throws {
        let session = HouseholdSession(store: InMemoryProfileStore())
        let erica = try session.addProfile(name: "Erica")
        #expect(AssistantAudience(session: session) == .guest)

        try session.switchManually(to: erica.id)
        let manual = AssistantAudience(session: session)
        #expect(manual.memberID == erica.id)
        #expect(manual.memberName == "Erica")
        #expect(!manual.isRecognized)
        #expect(!manual.isPersonalContentUnlocked)

        session.faceRecognized(profileID: erica.id, proximity: .near)
        let recognized = AssistantAudience(session: session)
        #expect(recognized.isRecognized)
        #expect(recognized.isPersonalContentUnlocked)

        session.requiresCompanionForPersonalContent = true
        let waitingForPhone = AssistantAudience(session: session)
        #expect(waitingForPhone.isRecognized)
        #expect(!waitingForPhone.isPersonalContentUnlocked)

        session.presenceLost()
        #expect(AssistantAudience(session: session) == .guest)
    }
}

@Suite struct PolicyTests {
    @Test func denial_whenGuest_thenSharedThingsOnly() {
        let allowed = AssistantPolicy.capabilities(for: .guest)
        #expect(allowed == [.timers, .navigation, .nightMode, .weather, .accessories, .climate, .screen])
        #expect(AssistantPolicy.denial(for: .scenes, audience: .guest) == .needsRecognizedMember)
        #expect(AssistantPolicy.denial(for: .browser, audience: .guest) == .needsHouseholdMember)
        #expect(AssistantPolicy.denial(for: .notes, audience: .guest) == .needsHouseholdMember)
    }

    @Test func denial_whenMemberPickedByHand_thenEverythingButScenes() {
        let allowed = AssistantPolicy.capabilities(for: Fixtures.manualErica)
        #expect(!allowed.contains(.scenes))
        #expect(allowed.contains(.browser))
        #expect(allowed.contains(.notes))
        #expect(AssistantPolicy.denial(for: .scenes, audience: Fixtures.manualErica) == .needsRecognizedMember)
    }

    @Test func denial_whenRecognizedMember_thenEverything() {
        #expect(AssistantPolicy.capabilities(for: Fixtures.recognizedLockedErica) == AssistantCapability.allCases)
    }

    @Test func allowedContext_whenGuest_thenNothingPersonal() {
        let context = AssistantPolicy.allowedContext(Fixtures.allItems, audience: .guest, usesPersonalContext: true)
        #expect(context.items == [Fixtures.timerItem, Fixtures.weatherItem])
        #expect(!context.containsPersonalItems)
    }

    @Test func allowedContext_whenMemberIsNotUnlocked_thenNothingPersonal() {
        for audience in [Fixtures.manualErica, Fixtures.recognizedLockedErica] {
            let context = AssistantPolicy.allowedContext(Fixtures.allItems, audience: audience, usesPersonalContext: true)
            #expect(context.items == [Fixtures.timerItem, Fixtures.weatherItem])
        }
    }

    @Test func allowedContext_whenUnlocked_thenOnlyTheActiveMembersOwnItems() {
        let context = AssistantPolicy.allowedContext(Fixtures.allItems, audience: Fixtures.unlockedErica, usesPersonalContext: true)
        #expect(context.items == [Fixtures.timerItem, Fixtures.weatherItem, Fixtures.ericaEvent, Fixtures.ericaReminder, Fixtures.ericaPlaylist])
        #expect(context.containsPersonalItems)
        #expect(context.entries.map(\.tag) == ["c1", "c2", "c3", "c4", "c5"])

        let dannys = AssistantPolicy.allowedContext(Fixtures.allItems, audience: Fixtures.unlockedDanny, usesPersonalContext: true)
        #expect(dannys.items == [Fixtures.timerItem, Fixtures.weatherItem, Fixtures.dannyReminder])
    }

    @Test func allowedContext_whenPersonalContextIsTurnedOff_thenNothingPersonalEvenWhenUnlocked() {
        let context = AssistantPolicy.allowedContext(Fixtures.allItems, audience: Fixtures.unlockedErica, usesPersonalContext: false)
        #expect(context.items == [Fixtures.timerItem, Fixtures.weatherItem])
    }

    @Test func allowedContext_whenRepeatsOrTooMany_thenDropsRepeatsAndStopsAtTheLimit() {
        let many = (0..<20).map { AssistantContextItem(id: "t\($0 % 12)", kind: .timer, title: "Timer \($0)") }
        let context = AssistantPolicy.allowedContext(many, audience: .guest, usesPersonalContext: true)
        #expect(context.items.count == AssistantLimits.maxContextItems)
        #expect(Set(context.items.map(\.id)).count == AssistantLimits.maxContextItems)
        #expect(AssistantAllowedContext.none.entries.isEmpty)
    }

    @Test func isPersonal_whenOwnedOrPersonalKind_thenTrue() {
        #expect(!Fixtures.timerItem.isPersonal)
        #expect(Fixtures.ericaPlaylist.isPersonal)
        #expect(Fixtures.ownerlessEvent.isPersonal)
        #expect(AssistantContextItem.Kind.allCases.filter(\.isAlwaysPersonal) == [.calendarEvent, .reminder])
    }

    @Test func itemsTagged_whenUnknownOrRepeatedTags_thenOnlyKnownItemsOnce() {
        let context = AssistantPolicy.allowedContext(Fixtures.allItems, audience: Fixtures.unlockedErica, usesPersonalContext: true)
        #expect(context.items(tagged: ["c3", "c9", "c3", "c1"]) == [Fixtures.ericaEvent, Fixtures.timerItem])
    }
}

@MainActor
@Suite struct RouterTests {
    private let actions = FakeActions()

    private func router(_ audience: AssistantAudience = Fixtures.unlockedErica, usesFahrenheit: Bool = false) -> AssistantRouter {
        AssistantRouter(actions: actions, audience: { audience }, usesFahrenheit: { usesFahrenheit })
    }

    @Test func perform_whenGuestAsksForAScene_thenRefusedAndTheHubIsNeverCalled() async {
        let report = await router(.guest).perform(.runScene(name: "Good Night"))
        #expect(report.result == .failure(.needsRecognizedMember))
        #expect(report.value == nil)
        #expect(actions.calls.isEmpty)
        #expect(report.modelText == "Not done. This needs a household member the hub's camera has recognized.")
    }

    @Test func perform_whenMemberPickedByHandAsksForAScene_thenRefused() async {
        let report = await router(Fixtures.manualErica).perform(.runScene(name: "Good Night"))
        #expect(report.result == .failure(.needsRecognizedMember))
        #expect(actions.calls.isEmpty)
    }

    @Test func perform_whenRecognizedMemberAsksForAScene_thenRuns() async {
        let report = await router(Fixtures.recognizedLockedErica).perform(.runScene(name: " Good\nNight "))
        #expect(report.value == .sceneRan("Good Night"))
        #expect(actions.calls == ["runScene Good Night"])
        #expect(report.modelText == "Scene Good Night ran.")
    }

    @Test func perform_whenGuestUsesSharedThings_thenAllowed() async {
        let router = router(.guest)
        #expect(await router.perform(.startTimer(name: nil, seconds: 60)).value == .timerStarted(Fixtures.timer("Timer", remaining: 60)))
        #expect(await router.perform(.setAccessory(name: "Lamp", isOn: true)).value == .accessory(AssistantAccessory(name: "Lamp", isOn: true)))
        #expect(await router.perform(.weather).value == .weather("Sunny and 68"))
        #expect(await router.perform(.setNightMode(isOn: true)).value == .nightMode(true))
        #expect(actions.calls == ["startTimer nil 60", "accessory Lamp true", "weather", "nightMode true"])
    }

    @Test func perform_whenGuestAsksForMemberThings_thenRefused() async {
        let router = router(.guest)
        #expect(await router.perform(.openWebPage(address: "https://example.com")).result == .failure(.needsHouseholdMember))
        #expect(await router.perform(.sendNote(text: "Hi")).result == .failure(.needsHouseholdMember))
        #expect(actions.calls.isEmpty)
    }

    @Test func perform_whenTimerRequests_thenValidatesAndReportsEach() async {
        let router = router()
        #expect(await router.perform(.startTimer(name: " Pasta ", seconds: 600)).modelText == "Timer Pasta started for 10 minutes.")
        #expect(await router.perform(.startTimer(name: "Too long", seconds: 86_401)).result == .failure(.invalid(.durationOutOfRange)))
        #expect(await router.perform(.startTimer(name: nil, seconds: 0)).result == .failure(.invalid(.durationOutOfRange)))
        #expect(await router.perform(.pauseTimer(name: "Pasta")).modelText == "Timer Pasta paused with 2 minutes left.")
        #expect(await router.perform(.cancelTimer(name: "  ")).modelText == "Timer Timer canceled.")
        #expect(await router.perform(.listTimers).modelText == "No timers are set.")
        actions.timerList = [Fixtures.timer("Pasta", remaining: 540), Fixtures.timer("Tea", remaining: 120, isPaused: true)]
        #expect(await router.perform(.listTimers).modelText == "Timers: Pasta, 9 minutes left; Tea, 2 minutes left (paused).")
        #expect(actions.calls == ["startTimer Pasta 600", "pauseTimer Pasta", "cancelTimer nil", "timers", "timers"])
    }

    @Test func perform_whenShowing_thenNeedsANameAndSaysWhatCameUp() async {
        let router = router()
        #expect(await router.perform(.show(name: "")).result == .failure(.invalid(.emptyName)))
        #expect(await router.perform(.show(name: "Solar")).modelText == "Showing the Solar face.")
        #expect(await router.perform(.show(name: "Weather")).modelText == "Opened Weather.")
        #expect(AssistantDestination.app("Weather").name == "Weather")
        #expect(await router.perform(.setNightMode(isOn: false)).modelText == "Night Mode is off.")
        #expect(await router.perform(.setNightMode(isOn: true)).modelText == "Night Mode is on.")
    }

    @Test func perform_whenHomeControls_thenValidatesNamesAndTemperature() async {
        #expect(await router().perform(.runScene(name: " ")).result == .failure(.invalid(.emptyName)))
        #expect(await router().perform(.setAccessory(name: "", isOn: true)).result == .failure(.invalid(.emptyName)))
        #expect(await router().perform(.setAccessory(name: "Desk Lamp", isOn: false)).modelText == "Desk Lamp is off.")
        #expect(await router().perform(.setAccessory(name: "Desk Lamp", isOn: true)).modelText == "Desk Lamp is on.")

        let celsius = await router().perform(.setThermostat(degrees: 21.3, scale: .hub))
        #expect(celsius.value == .thermostat(AssistantThermostat(name: "Hallway", targetCelsius: 21.5)))
        #expect(celsius.modelText == "Hallway set to 21.5 Celsius, which is 70.5 Fahrenheit.")
        let fahrenheit = await router(usesFahrenheit: true).perform(.setThermostat(degrees: 68, scale: .hub))
        #expect(fahrenheit.value == .thermostat(AssistantThermostat(name: "Hallway", targetCelsius: 20)))
        #expect(await router(usesFahrenheit: true).perform(.setThermostat(degrees: 20, scale: .celsius)).value == .thermostat(AssistantThermostat(name: "Hallway", targetCelsius: 20)))
        #expect(await router().perform(.setThermostat(degrees: 72, scale: .fahrenheit)).value == .thermostat(AssistantThermostat(name: "Hallway", targetCelsius: 22)))
        #expect(await router().perform(.setThermostat(degrees: 72, scale: .celsius)).result == .failure(.invalid(.temperatureOutOfRange)))
        #expect(await router().perform(.setThermostat(degrees: 2, scale: .celsius)).result == .failure(.invalid(.temperatureOutOfRange)))
    }

    @Test func perform_whenWebPage_thenOnlyHttpAndHttpsWithAHost() async {
        let router = router()
        let opened = await router.perform(.openWebPage(address: " https://example.com/recipes?id=4 "))
        #expect(opened.modelText == "Opened the page from example.com in the hub's browser.")
        for address in ["file:///etc/passwd", "javascript:alert(1)", "homepad://beam", "example.com", "https://", "https://user:secret@example.com", "http://" + String(repeating: "a", count: 2_100) + ".com"] {
            #expect(await router.perform(.openWebPage(address: address)).result == .failure(.invalid(.notAWebPage)))
        }
        #expect(actions.calls == ["openWebPage https://example.com/recipes?id=4"])
        #expect(AssistantActionReport.text(for: .pageOpened(URL(fileURLWithPath: "/tmp/page.html"))) == "Opened the page from the web in the hub's browser.")
    }

    @Test func perform_whenNote_thenFoldedToOneLineAndNeverEmpty() async {
        let router = router()
        #expect(await router.perform(.sendNote(text: " \n ")).result == .failure(.invalid(.emptyNote)))
        let sent = await router.perform(.sendNote(text: "Dinner\nat seven"))
        #expect(sent.modelText == "Note sent to 2 paired devices.")
        #expect(actions.calls == ["note Dinner at seven"])
        #expect(AssistantActionReport.text(for: .noteSent(AssistantNoteReceipt(recipientCount: 1))) == "Note sent to 1 paired device.")
    }

    @Test func perform_whenWeatherOrScreen_thenTextIsFoldedAndCut() async {
        actions.weather = "Rain\nlater. " + String(repeating: "word ", count: 200)
        let weather = await router().perform(.weather)
        #expect(weather.modelText.hasPrefix("Weather: Rain later."))
        #expect(weather.modelText.count <= AssistantLimits.maxToolTextCharacters + 9)
        #expect(await router().perform(.readScreen).modelText == "On screen: Clock face showing 2:05")
    }

    @Test func perform_whenTheHubFails_thenTheReasonIsPassedOn() async {
        actions.failure = .notFound("Disco")
        #expect(await router().perform(.runScene(name: "Disco")).modelText == "Not done. Nothing named Disco was found.")
        actions.failure = .personalContentLocked
        #expect(await router().perform(.show(name: "Calendar")).result == .failure(.personalContentLocked))
        actions.failure = .unavailable
        #expect(await router().perform(.weather).result == .failure(.unavailable))
    }

    @Test func modelText_whenEachError_thenSaysWhy() {
        let texts: [(AssistantActionError, String)] = [
            (.needsHouseholdMember, "The person is a guest and this needs a household member."),
            (.personalContentLocked, "This is personal and stays locked until its owner is recognized."),
            (.unavailable, "This is not available right now."),
            (.invalid(.emptyName), "A name is needed."),
            (.invalid(.durationOutOfRange), "A timer runs between one second and 24 hours."),
            (.invalid(.temperatureOutOfRange), "The temperature is outside what a thermostat accepts."),
            (.invalid(.notAWebPage), "Only web addresses that start with http or https can be opened."),
            (.invalid(.emptyNote), "The note is empty."),
            (.limitReached, "Too many actions for one request."),
        ]
        for (error, text) in texts {
            #expect(AssistantActionReport.text(for: error) == text)
        }
    }

    @Test func capability_whenEachRequest_thenNamesItsKind() {
        let pairs: [(AssistantRequest, AssistantCapability)] = [
            (.startTimer(name: nil, seconds: 1), .timers), (.pauseTimer(name: nil), .timers),
            (.cancelTimer(name: nil), .timers), (.listTimers, .timers), (.show(name: "x"), .navigation),
            (.setNightMode(isOn: true), .nightMode), (.runScene(name: "x"), .scenes),
            (.setThermostat(degrees: 20, scale: .celsius), .climate), (.setAccessory(name: "x", isOn: true), .accessories),
            (.weather, .weather), (.openWebPage(address: "x"), .browser), (.sendNote(text: "x"), .notes),
            (.readScreen, .screen),
        ]
        for (request, capability) in pairs {
            #expect(request.capability == capability)
        }
    }
}
