import XCTest

/// Walks the hub the way a person would and saves a screenshot of each stop. Set
/// TEST_RUNNER_HOMEPAD_SCREENSHOT_DIR to keep the images outside the result bundle, and
/// TEST_RUNNER_HOMEPAD_ORIENTATION=portrait to walk it upright.
@MainActor
final class HubWalkthroughTests: WalkthroughCase {
    private static let faceCount = 12

    override var snapshotPrefix: String { isPortraitRun ? "pt-" : "" }

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(isPad && !isDuoStandIn, "The hub walkthrough runs on a large iPad.")
        XCUIDevice.shared.orientation = isPortraitRun ? .portrait : .landscapeLeft
        capturesLandscape = !isPortraitRun
    }

    // MARK: First launch, as a guest across the room

    func testA_whenFirstLaunched_thenWelcomeHasNoPromptAndEveryFaceAndGuestAppAppears() throws {
        for resource in [XCUIProtectedResource.camera, .mediaLibrary, .homeKit, .location] {
            app.resetAuthorizationStatus(for: resource)
        }
        launch(Hook.ephemeral)

        let notNow = app.buttons["welcome.notNow"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 60), "the welcome did not appear")
        pause(4)
        XCTAssertFalse(isSystemPromptShowing, "a permission prompt covered the welcome")
        snapshot("a01-welcome")
        notNow.tap()

        pause(2)
        if isSystemPromptShowing {
            snapshot("a02-camera-prompt-after-welcome")
        }
        note("prompts answered after the welcome: \(allowSystemPrompts())")
        pause(1)

        walkFaces(prefix: "a1")

        openHomeScreen()
        snapshot("a30-home-guest-top")
        app.scrollViews["hub.homeScreen"].swipeUp()
        pause(1)
        snapshot("a31-home-guest-scrolled")
        app.scrollViews["hub.homeScreen"].swipeDown(velocity: .slow)
        pause(1)

        for id in ["timers", "home", "music", "recipes", "beam", "mirror", "weather", "clock", "people", "pairing"] {
            openApp(id, snapshotName: "a4-app-\(id)")
        }
        XCTAssertFalse(app.buttons["app.projectedApps"].exists, "a guest saw iPhone Apps, which is personal")
        XCTAssertFalse(app.buttons["app.messages"].exists, "Messages still has an icon")
        XCTAssertFalse(app.buttons["app.alarms"].exists, "a guest saw Alarms")
        XCTAssertFalse(app.buttons["app.intercom"].exists, "a guest has the Intercom icon, which is for members")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: A recognized member, up close, with sample content

    func testB_whenMemberRecognizedNear_thenFacesShowControlsAndEveryAppAndOverlayOpens() throws {
        launch(Hook.sample, Hook.audience("recognized"), Hook.proximity("near"), Hook.assistant)
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60), "the hub did not appear")
        pause(1)
        snapshot("b00-recognized-confirmation-in-pill")
        pause(5)
        XCTAssertFalse(app.buttons["welcome.notNow"].exists, "the welcome showed for an enrolled household")

        walkFaces(prefix: "b1")

        // The faces to choose from, after a held press.
        element("hub.faces").press(forDuration: 1.2)
        pause(1.5)
        snapshot("b20-face-picker")
        let customize = app.buttons["picker.customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 4), "the face picker did not open on a held press")
        // The row moves a face at a time; choose the one it settles on.
        edgeSwipe(fromX: 0.4, fromY: 0.5, toX: 0.7, toY: 0.5)
        pause(1.5)
        snapshot("b201-face-picker-after-a-swipe")
        tapWindow(x: 0.5, y: 0.5)
        pause(1.5)
        XCTAssertFalse(customize.exists, "choosing a face left the picker open")
        note("face chosen in the picker: \(currentFace)")

        homeFaceControls()

        openHomeScreen()
        snapshot("b30-home-member-top")
        app.scrollViews["hub.homeScreen"].swipeUp()
        pause(1)
        snapshot("b31-home-member-scrolled")
        app.scrollViews["hub.homeScreen"].swipeDown(velocity: .slow)
        pause(1)

        XCTAssertFalse(app.buttons["app.messages"].exists, "Messages still has an icon")
        for id in ["projectedApps", "photos", "weather", "music", "clock"] {
            openApp(id, snapshotName: "b4-app-\(id)")
        }
        homeApp()

        // Alarms: set a time with the large arrows and add it.
        if tapApp("alarms") {
            snapshot("b4-app-alarms")
            app.buttons["alarms.hour.up"].tap()
            app.buttons["alarms.minute.up"].tap()
            app.buttons["alarms.add"].tap()
            pause(1)
            snapshot("b45-alarm-added")
            closeApp()
        }

        // Timers: start one, see the ring, then the list, then the pill on the face.
        if tapApp("timers") {
            snapshot("b50-timers-presets")
            app.buttons["timers.preset.15"].tap()
            pause(2)
            snapshot("b51-timer-ring")
            app.buttons["timers.all"].tap()
            pause(1)
            snapshot("b52-timers-list")
            app.buttons["hub.close"].firstMatch.tap()
            pause(1)
            app.buttons["hub.showFace"].firstMatch.tap()
            pause(2)
            snapshot("b53-face-with-live-pill")
            let pill = app.buttons["hub.pill"]
            XCTAssertTrue(pill.waitForExistence(timeout: 4), "the running timer is not in the pill")
            pill.tap()
            pause(1.5)
            snapshot("b54-live-pill-expanded")
            XCTAssertTrue(element("hub.pillCard").exists, "the pill did not expand")
            element("hub.pillCard").tap()
            pause(1)
            openHomeScreen()
        }

        // Recipes: the sample page stands in for the network.
        if tapApp("recipes") {
            snapshot("b60-recipes-entry")
            let field = app.textFields["recipes.link"]
            field.tap()
            field.typeText("example.com/soup\n")
            // The page's own recipe shows at once. The tidied one takes its place a moment later.
            XCTAssertTrue(app.buttons["recipes.cook"].waitForExistence(timeout: 5), "the recipe's cover did not appear")
            snapshot("b61-recipe-cover-as-the-page-gave-it")
            pause(4)
            snapshot("b611-recipe-cover-tidied")
            app.buttons["recipes.ingredients"].tap()
            pause(1)
            app.buttons["4 cups vegetable stock"].firstMatch.tap()
            pause(0.5)
            snapshot("b62-recipe-ingredients")
            XCTAssertTrue(element("recipes.tidiedNote").exists, "the ingredient list does not say the recipe was tidied")
            app.buttons["recipes.back"].tap()
            pause(1)
            app.buttons["recipes.cook"].tap()
            pause(1)
            snapshot("b63-recipe-step-1")
            XCTAssertTrue(element("recipes.stepTitle").exists, "a tidied step has no short title")
            app.buttons["recipes.next"].tap()
            pause(1)
            snapshot("b64-recipe-step-2-with-its-ingredients")
            XCTAssertTrue(element("recipes.timerPill").exists, "the running timer is not floating over the recipe")
            XCTAssertTrue(element("recipes.stepIngredients").exists, "the step does not show the ingredients it uses")
            // To the page's own words and back, without losing the place.
            app.buttons["recipes.toggleOriginal"].tap()
            pause(1.5)
            snapshot("b65-recipe-original-text")
            XCTAssertFalse(element("recipes.stepTitle").exists, "the original text still shows a tidied title")
            XCTAssertEqual(element("recipes.stepBadge").label, "Step 1 of 4", "switching to the original lost the place")
            app.buttons["recipes.toggleOriginal"].tap()
            pause(1.5)
            snapshot("b66-recipe-tidied-again")
            XCTAssertEqual(element("recipes.stepBadge").label, "Step 1 of 7", "switching back did not return to the tidied recipe")
            app.buttons["recipes.stopCooking"].tap()
            pause(1)
            app.buttons["recipes.closeRecipe"].tap()
            pause(1)
            closeApp()
        }

        controlCenter(prefix: "b7")

        // The assistant, from its control in the status area and from the control center.
        let assistant = app.buttons["hub.assistant"].firstMatch
        XCTAssertTrue(assistant.waitForExistence(timeout: 4), "the status area has no assistant control")
        if assistant.exists {
            assistant.tap()
            pause(2.5)
            snapshot("b80-assistant")
            XCTAssertTrue(element("hub.assistantOpen").exists, "the assistant did not open from the status area")
            askAssistant("What time is it?")
            snapshot("b801-assistant-answered")
            closeAssistant()
            app.buttons["hub.profile"].firstMatch.tap()
            pause(1.5)
            app.buttons["control.assistant"].firstMatch.tap()
            pause(2.5)
            snapshot("b81-assistant-from-control-center")
            XCTAssertTrue(element("hub.assistantOpen").exists, "the assistant did not open from the control center")
            closeAssistant()
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: On approach: labels without controls

    func testC_whenMemberAtMiddleDistance_thenLabelsShowAndControlsDoNot() throws {
        launch(Hook.sample, Hook.audience("recognized"), Hook.proximity("mid"))
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60), "the hub did not appear")
        pause(6)
        walkFaces(prefix: "c1")
        XCTAssertFalse(app.buttons["home.thermostat.up"].exists, "the thermostat steppers showed at the middle distance")
        cookSampleRecipe()
        snapshot("c30-mid-recipe-step")
        XCTAssertTrue(element("recipes.stepIngredients").exists, "the step's ingredients are missing at the middle distance")
        XCTAssertFalse(app.buttons["recipes.next"].exists, "the step buttons showed at the middle distance")

        // Across the room, with the same home: the large numbers only.
        launch(Hook.sample, Hook.audience("recognized"), Hook.proximity("far"))
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60), "the hub did not appear")
        pause(6)
        snapshot("c20-far-modular")
        for (index, title) in ["Weather", "Home Modular", "Calendar"].enumerated() {
            swipeToFace(title)
            snapshot("c2\(index + 1)-far-\(slug(title))")
        }
        cookSampleRecipe()
        snapshot("c31-far-recipe-step")
        XCTAssertFalse(element("recipes.stepIngredients").exists, "the step's ingredients showed from across the room")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Night Mode on every screen

    func testD_whenNightMode_thenEveryScreenIsRedOnBlackAndTheSwitchTurnsItOff() throws {
        launch(Hook.sample, Hook.audience("recognized"), Hook.proximity("near"), Hook.night, Hook.assistant)
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60), "the hub did not appear")
        pause(6)
        walkFaces(prefix: "n1")

        element("hub.faces").press(forDuration: 1.2)
        pause(1.5)
        snapshot("n20-face-picker-night")
        tapWindow(x: 0.5, y: 0.5)
        pause(1.5)

        openHomeScreen()
        snapshot("n30-home-screen-night")
        for id in ["home", "music", "weather", "timers", "projectedApps"] {
            openApp(id, snapshotName: "n4-app-\(id)-night")
        }
        if tapApp("home") {
            element("home.thermostat").tap()
            pause(1.5)
            snapshot("n50-thermostat-dial-night")
            app.buttons["overlay.close"].firstMatch.tap()
            pause(1)
            closeApp()
        }

        cookSampleRecipe()
        snapshot("n51-recipe-step-night")
        app.buttons["recipes.stopCooking"].tap()
        pause(1)
        app.buttons["recipes.closeRecipe"].tap()
        pause(1)
        closeApp()

        app.buttons["hub.assistant"].firstMatch.tap()
        pause(1.5)
        snapshot("n60-assistant-night")
        XCTAssertTrue(element("hub.assistantOpen").exists, "the assistant did not open from the status area")
        askAssistant("What time is it?")
        snapshot("n61-assistant-answered-night")
        closeAssistant()

        app.buttons["hub.profile"].firstMatch.tap()
        pause(1.5)
        snapshot("n70-control-center-night")
        let night = app.buttons["control.night"]
        XCTAssertTrue(night.waitForExistence(timeout: 4), "the control center has no Night Mode switch")
        night.tap()
        pause(2)
        snapshot("n71-control-center-after-night-switched-off")
        tapWindow(x: 0.02, y: 0.5)
        pause(1.5)
        snapshot("n72-home-screen-day-again")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Other audiences, the square canvas, solid glass, and transitions part way

    func testE_whenOtherAudiencesAndLayouts_thenEachBehaves() throws {
        // A guest: scenes are shown and do not run, and nothing personal is anywhere.
        launch(Hook.sample, Hook.audience("guest"), Hook.proximity("near"))
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60))
        pause(2)
        snapshot("e10-face-guest-near")
        swipeToFace("Home Modular")
        snapshot("e11-home-modular-guest")
        openHomeScreen()
        snapshot("e12-home-screen-guest")
        XCTAssertFalse(app.buttons["app.projectedApps"].exists, "a guest saw iPhone Apps, which is personal")
        if tapApp("home") {
            snapshot("e13-home-app-guest-scenes-locked")
            XCTAssertTrue(element("home.scenesLocked").exists, "the scenes note is missing for a guest")
            closeApp()
        }
        controlCenter(prefix: "e1", isGuest: true)

        // A profile picked by hand: personal items are there, greyed out, and do not open.
        launch(Hook.sample, Hook.audience("manual"), Hook.proximity("near"))
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60))
        pause(2)
        openHomeScreen()
        snapshot("e20-home-screen-manual-profile-redacted")
        XCTAssertTrue(app.buttons["app.projectedApps"].exists, "iPhone Apps is missing for a manually chosen profile")
        XCTAssertFalse(app.buttons["app.projectedApps"].isEnabled, "iPhone Apps opened without a face match")

        // A camera match is waiting and Touch ID is offered, on a simulator that has neither.
        launch(Hook.sample, Hook.audience("guest"), Hook.proximity("near"), Hook.deviceUnlock)
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60))
        pause(2)
        XCTAssertTrue(app.buttons["hub.deviceUnlock"].exists, "the Touch ID button is missing from the status")
        openHomeScreen()
        snapshot("e40-home-screen-touch-id-offered")
        let lockedApp = app.buttons["app.projectedApps"]
        XCTAssertTrue(lockedApp.isEnabled, "a locked app should accept a tap while Touch ID is offered")
        lockedApp.tap()
        pause(2.5)
        snapshot("e42-iphone-apps-opened-after-touch-id")
        XCTAssertTrue(app.buttons["hub.close"].firstMatch.exists, "iPhone Apps did not open after the unlock")

        // The square canvas, kept as an option.
        launch(Hook.sample, Hook.audience("recognized"), Hook.proximity("near"), Hook.square)
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60))
        pause(6)
        swipeToFace("Home Modular")
        snapshot("e50-square-home-modular")
        openHomeScreen()
        snapshot("e51-square-home-screen")

        // Solid fills in place of glass, as with Reduce Transparency.
        launch(Hook.sample, Hook.audience("recognized"), Hook.proximity("near"), Hook.solidGlass)
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60))
        pause(6)
        swipeToFace("Home Modular")
        snapshot("e60-solid-glass-home-modular")
        app.buttons["hub.profile"].firstMatch.tap()
        pause(1.5)
        snapshot("e61-solid-glass-control-center")
        tapWindow(x: 0.02, y: 0.5)
        pause(1)
        openHomeScreen()
        snapshot("e62-solid-glass-home-screen")

        // Transitions slowed down eight times, caught part way.
        launch(Hook.sample, Hook.audience("recognized"), Hook.proximity("near"), Hook.slowMotion(8), Hook.assistant)
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60))
        pause(6)
        swipeToFace("Home Modular")
        edgeSwipe(fromX: 0.5, fromY: 0.985, toX: 0.5, toY: 0.55)
        frames("f1-face-to-home-screen", count: 4)
        pause(3)
        let music = app.buttons["app.music"]
        if music.waitForExistence(timeout: 4) {
            music.tap()
            frames("f2-app-opens-from-icon", count: 5)
            pause(3)
            app.buttons["hub.close"].firstMatch.tap()
            frames("f3-app-closes-into-icon", count: 4)
            pause(3)
        }
        edgeSwipe(fromX: 0.9, fromY: 0.01, toX: 0.9, toY: 0.4)
        frames("f4-control-center-opens", count: 4)
        pause(3)
        XCTAssertTrue(app.buttons["control.night"].exists, "a swipe down from the top trailing corner did not open the control center")
        app.buttons["control.night"].tap()
        frames("f5-night-comes-on", count: 6)
        pause(6)
        snapshot("f51-night-on-settled")
        app.buttons["control.night"].tap()
        pause(8)
        snapshot("f52-day-again-settled")
        tapWindow(x: 0.02, y: 0.5)
        pause(4)
        edgeSwipe(fromX: 0.5, fromY: 0.01, toX: 0.5, toY: 0.4)
        pause(4)
        snapshot("f6-assistant-after-pull-from-top-center")
        XCTAssertTrue(element("hub.assistantOpen").exists, "a pull down from the top center did not open the assistant")
        closeAssistant()
        pause(3)
        snapshot("f7-home-screen-still-there-after-the-assistant")
        XCTAssertTrue(app.scrollViews["hub.homeScreen"].exists, "the pull that opened the assistant also left the Home Screen")
        // A pull from the leading part of the top edge is the one that goes back to the face.
        edgeSwipe(fromX: 0.15, fromY: 0.01, toX: 0.15, toY: 0.4)
        pause(4)
        XCTAssertFalse(app.scrollViews["hub.homeScreen"].exists, "a pull down from the top edge did not return to the face")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Steps

    private var currentFace: String {
        (app.otherElements["hub.currentFace"].value as? String) ?? ""
    }

    /// Swipes until the face in front changes. A swipe can be dropped while a face is animating,
    /// so it is retried, and each retry is written to the notes.
    @discardableResult
    private func swipeToNextFace(forward: Bool = true) -> Bool {
        let before = currentFace
        for attempt in 1...3 {
            edgeSwipe(fromX: forward ? 0.8 : 0.2, fromY: 0.5, toX: forward ? 0.2 : 0.8, toY: 0.5)
            pause(1.5)
            if before.isEmpty || currentFace != before { return true }
            note("swipe \(attempt) from \(before) did not change the face")
        }
        return false
    }

    /// Goes forward through the faces, then back from the last one, until the named face is
    /// in front.
    private func swipeToFace(_ title: String) {
        var forward = true
        for _ in 0..<(Self.faceCount * 2) where currentFace != title {
            if !swipeToNextFace(forward: forward) {
                guard forward else { break }
                forward = false
            }
        }
        XCTAssertEqual(currentFace, title, "could not reach the \(title) face")
        pause(1)
    }

    private func walkFaces(prefix: String) {
        var seen: [String] = []
        for index in 1...(Self.faceCount + 2) {
            let name = currentFace
            if !name.isEmpty, seen.contains(name) { break }
            seen.append(name)
            if allowSystemPrompts(wait: 1) > 0 {
                note("a prompt was answered on \(name)")
                pause(1)
            }
            snapshot(String(format: "%@%02d-face-%@", prefix, index, slug(name.isEmpty ? "unknown" : name)))
            if index == Self.faceCount && name.isEmpty { break }
            guard swipeToNextFace() else { break }
        }
        note("\(prefix) faces seen in order: \(seen.joined(separator: ", "))")
        XCTAssertEqual(seen.count, Self.faceCount, "expected every face once, saw \(seen)")
        XCTAssertEqual(seen.last, "Rainbow", "the last face should be Rainbow")
    }

    /// Several screenshots in a row, as fast as they can be taken, to catch a transition.
    private func frames(_ name: String, count: Int) {
        for index in 1...count {
            snapshot("\(name)-\(index)")
        }
    }

    /// Opens the sample recipe from the Home Screen and goes to a step that uses ingredients,
    /// once the tidied recipe has arrived. Across the room there are no step buttons, so the
    /// step is chosen before the cook steps back: the reader starts on the first step.
    private func cookSampleRecipe() {
        if !app.scrollViews["hub.homeScreen"].exists {
            openHomeScreen()
        }
        guard tapApp("recipes") else { return }
        let field = app.textFields["recipes.link"]
        field.tap()
        field.typeText("example.com/soup\n")
        XCTAssertTrue(app.buttons["recipes.cook"].waitForExistence(timeout: 5), "the recipe's cover did not appear")
        pause(4)
        app.buttons["recipes.cook"].tap()
        pause(1)
        let next = app.buttons["recipes.next"]
        if next.exists {
            next.tap()
            pause(1)
        }
    }

    private func closeApp() {
        let close = app.buttons["hub.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 4), "the app has no close button")
        close.tap()
        pause(1)
        // Opening an app can leave the Home Screen scrolled. Start each search from the top.
        app.scrollViews["hub.homeScreen"].swipeDown(velocity: .slow)
        pause(0.6)
    }

    private func openApp(_ id: String, snapshotName: String) {
        guard tapApp(id) else { return }
        snapshot(snapshotName)
        closeApp()
    }

    /// On the Home Modular face: a tap switches a tile, a held press opens the dimmer, the
    /// thermostat opens its dial, and the camera opens full screen.
    private func homeFaceControls() {
        swipeToFace("Home Modular")
        let light = app.buttons["home.tile.accessory.entry"]
        guard light.waitForExistence(timeout: 4) else {
            note("the entry light is not on the Home Modular face at this size")
            return
        }
        light.tap()
        pause(1)
        snapshot("b21-home-modular-light-switched-off")
        light.tap()
        pause(1)
        light.press(forDuration: 1)
        pause(1.5)
        snapshot("b22-dimmer")
        let track = element("dimmer.track")
        XCTAssertTrue(track.exists, "a held press on a light did not open the dimmer")
        if track.exists {
            track.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
            pause(1)
            snapshot("b23-dimmer-set-low")
        }
        tapWindow(x: 0.03, y: 0.5)
        pause(1)

        element("home.thermostat").tap()
        pause(1.5)
        snapshot("b24-thermostat-dial")
        let dial = element("thermostat.dial")
        XCTAssertTrue(dial.exists, "a tap on the thermostat did not open the dial")
        if dial.exists {
            dial.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45)).tap()
            pause(1)
            app.buttons["thermostat.mode.2"].firstMatch.tap()
            pause(1)
            snapshot("b25-thermostat-dial-dragged-and-cool")
        }
        app.buttons["overlay.close"].firstMatch.tap()
        pause(1)

        let camera = app.buttons["home.tile.camera.porch"]
        if camera.exists {
            camera.tap()
            pause(1.5)
            snapshot("b26-camera-zoomed")
            XCTAssertFalse(app.buttons["camera.talk"].exists, "a microphone button showed for a camera without two-way audio")
            app.buttons["overlay.close"].firstMatch.tap()
            pause(1)
        }
    }

    /// The Home app: the room bar, and the same controls from inside an app.
    private func homeApp() {
        guard tapApp("home") else { return }
        snapshot("b4-app-home")
        let office = app.buttons["home.room.Office"]
        if office.waitForExistence(timeout: 3) {
            office.tap()
            pause(1.5)
            snapshot("b46-home-app-room-office")
            app.buttons["home.room.all"].tap()
            pause(1)
        } else {
            XCTFail("the Home app has no room bar")
        }
        element("home.thermostat").tap()
        pause(1.5)
        snapshot("b47-home-app-thermostat-dial")
        app.buttons["overlay.close"].firstMatch.tap()
        pause(1)
        closeApp()
    }

    /// Opens the control center from the status, captures it, and closes it by its backdrop.
    private func controlCenter(prefix: String, isGuest: Bool = false) {
        app.buttons["hub.profile"].firstMatch.tap()
        pause(1.5)
        snapshot("\(prefix)0-control-center")
        XCTAssertTrue(app.buttons["control.night"].exists, "the control center did not open")
        if isGuest {
            XCTAssertFalse(app.buttons["control.intercom"].exists, "a guest has the Intercom control, which is for members")
        } else {
            note("Intercom control in the control center: \(app.buttons["control.intercom"].exists)")
        }
        let quiet = app.buttons["control.quiet"]
        if quiet.exists {
            quiet.tap()
            pause(1)
            snapshot("\(prefix)1-control-center-do-not-disturb-on")
            quiet.tap()
            pause(0.5)
        }
        tapWindow(x: 0.02, y: 0.5)
        pause(1)
        XCTAssertFalse(app.buttons["control.night"].exists, "a tap outside did not close the control center")
    }
}
