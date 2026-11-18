import XCTest

/// Walks the hub the way a person would and saves a screenshot of each stop. Set
/// TEST_RUNNER_HOMEPAD_SCREENSHOT_DIR to keep the images outside the result bundle.
@MainActor
final class HubWalkthroughTests: WalkthroughCase {
    private static let faceCount = 11

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(isPad && !isDuoStandIn, "The hub walkthrough runs on a large iPad.")
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    // MARK: First launch, as a guest across the room

    func testA_whenFirstLaunched_thenWelcomeHasNoPromptAndEveryFaceAndGuestAppAppears() throws {
        for resource in [XCUIProtectedResource.camera, .mediaLibrary, .homeKit] {
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
        app.scrollViews["hub.homeScreen"].swipeDown()
        pause(1)

        for id in ["timers", "home", "music", "recipes", "beam", "mirror", "weather", "clock", "people", "pairing"] {
            openApp(id, snapshotName: "a4-app-\(id)")
        }
        XCTAssertFalse(app.buttons["app.messages"].exists, "a guest saw Messages")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: A recognized member, up close, with sample content

    func testB_whenMemberRecognizedNear_thenFacesShowDetailAndPersonalAppsOpen() throws {
        launch(Hook.sample, Hook.audience("recognized"), Hook.proximity("near"))
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60), "the hub did not appear")
        pause(2)
        XCTAssertFalse(app.buttons["welcome.notNow"].exists, "the welcome showed for an enrolled household")

        walkFaces(prefix: "b1")

        openHomeScreen()
        snapshot("b30-home-member-top")
        app.scrollViews["hub.homeScreen"].swipeUp()
        pause(1)
        snapshot("b31-home-member-scrolled")
        app.scrollViews["hub.homeScreen"].swipeDown()
        pause(1)

        for id in ["messages", "projectedApps", "photos", "home", "weather", "music", "clock"] {
            openApp(id, snapshotName: "b4-app-\(id)")
        }

        // Alarms: set a time with the large arrows and add it.
        if tapApp("alarms") {
            snapshot("b4-app-alarms")
            app.buttons["alarms.hour.up"].tap()
            app.buttons["alarms.minute.up"].tap()
            app.buttons["alarms.add"].tap()
            pause(1)
            snapshot("b45-alarm-added")
            app.buttons["hub.close"].firstMatch.tap()
            pause(1)
            app.scrollViews["hub.homeScreen"].swipeDown(velocity: .slow)
            pause(0.6)
        }

        // Timers: start one, see the ring, then the list, then the strip on the face.
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
            app.buttons["hub.showFace"].tap()
            pause(2)
            snapshot("b53-face-with-timer-strip")
            openHomeScreen()
        }

        // Recipes: the sample page stands in for the network.
        if tapApp("recipes") {
            snapshot("b60-recipes-entry")
            let field = app.textFields["recipes.link"]
            field.tap()
            field.typeText("example.com/soup\n")
            pause(3)
            snapshot("b61-recipe-cover")
            app.buttons["recipes.ingredients"].tap()
            pause(1)
            snapshot("b62-recipe-ingredients")
            app.buttons["recipes.back"].tap()
            pause(1)
            app.buttons["recipes.cook"].tap()
            pause(1)
            snapshot("b63-recipe-step-1")
            app.buttons["recipes.next"].tap()
            pause(1)
            snapshot("b64-recipe-step-2")
            app.buttons["recipes.stopCooking"].tap()
            pause(1)
            app.buttons["recipes.closeRecipe"].tap()
            pause(1)
            app.buttons["hub.close"].firstMatch.tap()
            pause(1)
        }

        app.buttons["hub.profile"].firstMatch.tap()
        pause(1.5)
        snapshot("b70-profile-switcher")
        app.buttons["switcher.done"].tap()
        pause(1)
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Other audiences and layouts

    func testC_whenGuestWithSampleHome_thenScenesAreShownLockedAndFillLayoutHasASecondColumn() throws {
        launch(Hook.sample, Hook.audience("guest"), Hook.proximity("near"), Hook.fill)
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60))
        pause(2)
        snapshot("c10-fill-face-guest-near")
        swipeToNextFace()
        swipeToNextFace()
        swipeToNextFace()
        snapshot("c11-fill-home-modular-guest")
        openHomeScreen()
        snapshot("c12-fill-home-screen-guest")
        if tapApp("home") {
            snapshot("c13-home-app-guest-scenes-locked")
            XCTAssertTrue(app.descendants(matching: .any)["home.scenesLocked"].firstMatch.exists, "the scenes note is missing for a guest")
            app.buttons["hub.close"].firstMatch.tap()
            pause(1)
        }

        launch(Hook.sample, Hook.audience("manual"), Hook.proximity("near"))
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60))
        pause(2)
        openHomeScreen()
        snapshot("c20-home-screen-manual-profile-redacted")
        XCTAssertTrue(app.buttons["app.messages"].exists, "Messages is missing for a manually chosen profile")
        XCTAssertFalse(app.buttons["app.messages"].isEnabled, "Messages opened without a face match")

        // A camera match is waiting and Touch ID is offered, on a simulator that has neither.
        launch(Hook.sample, Hook.audience("guest"), Hook.proximity("near"), Hook.deviceUnlock)
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60))
        pause(2)
        XCTAssertTrue(app.buttons["hub.deviceUnlock"].exists, "the Touch ID button is missing beside the canvas")
        openHomeScreen()
        snapshot("c40-home-screen-touch-id-offered")
        app.buttons["hub.profile"].firstMatch.tap()
        pause(1.5)
        snapshot("c41-profile-switcher-touch-id-offered")
        app.buttons["switcher.done"].tap()
        pause(1)
        let lockedMessages = app.buttons["app.messages"]
        XCTAssertTrue(lockedMessages.isEnabled, "a locked app should accept a tap while Touch ID is offered")
        lockedMessages.tap()
        pause(2.5)
        snapshot("c42-messages-opened-after-touch-id")
        XCTAssertTrue(app.buttons["hub.close"].firstMatch.exists, "Messages did not open after the unlock")
        XCTAssertFalse(app.buttons["hub.deviceUnlock"].exists, "the Touch ID button stayed after unlocking")

        launch(Hook.sample, Hook.audience("recognized"), Hook.proximity("far"), Hook.night)
        XCTAssertTrue(app.otherElements["hub.nightClock"].waitForExistence(timeout: 60))
        pause(4)
        snapshot("c30-night-clock")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Steps

    private var currentFace: String {
        (app.otherElements["hub.currentFace"].value as? String) ?? ""
    }

    /// Swipes until the face in front changes. A swipe can be dropped while a face is animating,
    /// so it is retried, and each retry is written to the notes.
    @discardableResult
    private func swipeToNextFace() -> Bool {
        let before = currentFace
        for attempt in 1...3 {
            app.swipeLeft()
            pause(1.5)
            if before.isEmpty || currentFace != before { return true }
            note("swipe \(attempt) from \(before) did not change the face")
        }
        return false
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

    private func openApp(_ id: String, snapshotName: String) {
        guard tapApp(id) else { return }
        snapshot(snapshotName)
        let close = app.buttons["hub.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 4), "\(id) has no close button")
        close.tap()
        pause(1)
        // Opening an app can leave the Home Screen scrolled. Start each search from the top.
        app.scrollViews["hub.homeScreen"].swipeDown(velocity: .slow)
        pause(0.6)
    }
}
