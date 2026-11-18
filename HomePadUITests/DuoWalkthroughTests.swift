import XCTest

/// Captures the layouts a folding iPhone gets. No simulator for it runs on this machine, so the
/// small iPad frames the whole app to the sizes of its two displays, in points, through a test
/// hook. The inner display is 626 by 890 and the outer one 466 by 678.
@MainActor
final class DuoWalkthroughTests: WalkthroughCase {
    private enum Size {
        static let inner = "626x890"
        static let innerOnItsSide = "890x626"
        static let outer = "466x678"
        static let outerOnItsSide = "678x466"
    }

    override var usesEdgeSwipes: Bool { false }

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(isDuoStandIn, "The folding iPhone sizes are framed on the small iPad.")
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Companion

    func testA_whenCompanionOnEachDisplay_thenTabsWhenCompactAndTwoColumnsWhenRegular() throws {
        let companion = Hook.role("companion")

        // Outer display: compact width, so tabs.
        launch(companion, Hook.sample, Hook.viewport(Size.outer))
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 60), "the outer display should show tabs")
        settle()
        snapshot("d10-outer-companion-hub-summary")
        for (index, title) in ["Beam", "Apps", "People"].enumerated() {
            let tab = tabs.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "the \(title) tab is missing")
            tab.tap()
            pause(1.5)
            snapshot("d1\(index + 1)-outer-companion-\(slug(title))")
        }
        launch(companion, Hook.viewport(Size.outer))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 60))
        settle()
        snapshot("d14-outer-companion-hub-not-reachable")

        // Inner display: regular width, so the hub's status and the sections beside the content.
        launch(companion, Hook.sample, Hook.viewport(Size.inner))
        let apps = section("apps")
        XCTAssertTrue(apps.waitForExistence(timeout: 60), "the inner display should list the sections")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "the inner display should not show tabs")
        settle()
        snapshot("d20-inner-companion-beam")
        apps.tap()
        pause(1.5)
        snapshot("d21-inner-companion-apps")
        section("people").tap()
        pause(1.5)
        snapshot("d22-inner-companion-people")
        launch(companion, Hook.viewport(Size.inner))
        XCTAssertTrue(section("apps").waitForExistence(timeout: 60))
        settle()
        snapshot("d23-inner-companion-hub-not-reachable")

        // A companion on the whole iPad, as when the role is set to Companion in Settings.
        launch(companion, Hook.sample)
        XCTAssertTrue(section("apps").waitForExistence(timeout: 60), "an iPad companion should list the sections")
        settle()
        snapshot("d40-ipad-companion")

        XCUIDevice.shared.orientation = .landscapeLeft
        pause(1)
        launch(companion, Hook.sample, Hook.viewport(Size.innerOnItsSide))
        XCTAssertTrue(section("people").waitForExistence(timeout: 60))
        settle()
        snapshot("d30-inner-landscape-companion-beam")
        section("people").tap()
        pause(1.5)
        snapshot("d31-inner-landscape-companion-people")

        launch(companion, Hook.sample, Hook.viewport(Size.outerOnItsSide))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 60), "the outer display on its side should show tabs")
        settle()
        snapshot("d32-outer-landscape-companion-hub-summary")
        app.tabBars.firstMatch.buttons["Beam"].tap()
        pause(1.5)
        snapshot("d33-outer-landscape-companion-beam")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Hub

    func testB_whenHubOnEachDisplay_thenTheHubFillsEachAndTheStatusFits() throws {
        let member = [Hook.sample, Hook.audience("recognized"), Hook.proximity("near")]

        hub(member, Hook.viewport(Size.inner))
        snapshot("h10-inner-hub-face")
        openHomeScreen()
        snapshot("h11-inner-hub-home-screen")
        if tapApp("alarms") {
            snapshot("h12-inner-hub-alarms")
        }

        hub(member, Hook.viewport(Size.outer))
        snapshot("h20-outer-hub-face")
        openHomeScreen()
        snapshot("h21-outer-hub-home-screen")
        if tapApp("alarms") {
            snapshot("h22-outer-hub-alarms")
            app.buttons["hub.close"].firstMatch.tap()
            pause(1)
        }
        app.buttons["hub.profile"].firstMatch.tap()
        pause(1.5)
        snapshot("h23-outer-hub-control-center")
        XCTAssertTrue(app.buttons["control.night"].exists, "the control center did not open on the outer display")

        hub(member, Hook.viewport(Size.outer), Hook.night)
        snapshot("h24-outer-hub-face-night")

        hub(member, Hook.viewport(Size.inner), Hook.square)
        snapshot("h50-inner-hub-square-canvas")

        // The Home Modular face and its dial on the inner display.
        hub(member, Hook.viewport(Size.inner))
        for _ in 0..<4 {
            app.swipeLeft()
            pause(1.2)
        }
        snapshot("h51-inner-hub-home-modular")
        let thermostat = app.descendants(matching: .any)["home.thermostat"].firstMatch
        if thermostat.exists {
            thermostat.tap()
            pause(1.5)
            snapshot("h52-inner-hub-thermostat-dial")
        }

        // Partly folded, held upright: the fold runs across, the face above and the rest below.
        hub(member, Hook.viewport(Size.inner), Hook.fold)
        snapshot("h43-inner-hub-folded-across")

        XCUIDevice.shared.orientation = .landscapeLeft
        pause(1)
        hub(member, Hook.viewport(Size.innerOnItsSide))
        snapshot("h30-inner-landscape-hub-face")
        openHomeScreen()
        snapshot("h31-inner-landscape-hub-home-screen")

        hub(member, Hook.viewport(Size.outerOnItsSide))
        snapshot("h32-outer-landscape-hub-face")

        // Partly folded like a book: the face on one side, the status, timers, and widgets on
        // the other.
        hub(member, Hook.viewport(Size.innerOnItsSide), Hook.fold)
        snapshot("h40-inner-hub-folded-face")
        openHomeScreen()
        snapshot("h41-inner-hub-folded-home-screen")
        if tapApp("timers") {
            app.buttons["timers.preset.15"].tap()
            pause(1.5)
            app.buttons["hub.showFace"].firstMatch.tap()
            pause(2)
            snapshot("h42-inner-hub-folded-face-with-timer")
            XCTAssertTrue(app.buttons["hub.timerStrip"].exists, "the running timer is missing from the folded layout")
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Steps

    /// After a launch: answers a system prompt if one is up, so it is not in the screenshot.
    private func settle() {
        if allowSystemPrompts(wait: 2) > 0 {
            note("a prompt was answered after a companion launch")
        }
        pause(1.5)
    }

    private func section(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)["companion.section.\(id)"].firstMatch
    }

    private func hub(_ member: [[String: String]], _ hooks: [String: String]...) {
        launch(member + hooks)
        XCTAssertTrue(app.buttons["hub.showHomeScreen"].waitForExistence(timeout: 60), "the hub did not appear")
        allowSystemPrompts(wait: 1)
        pause(2)
    }
}
