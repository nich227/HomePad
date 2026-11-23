import XCTest

/// Walks the iPhone companion's tabs and saves a screenshot of each.
@MainActor
final class CompanionWalkthroughTests: WalkthroughCase {
    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipIf(isPad, "The companion walkthrough runs on an iPhone.")
        XCUIDevice.shared.orientation = .portrait
    }

    func testA_whenLaunchedOnPhone_thenEveryTabAppears() throws {
        launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 60), "the companion's tab bar did not appear")
        note("prompts answered at launch: \(allowSystemPrompts())")
        pause(1)
        snapshot("p10-companion-hub-not-reachable")
        for (index, title) in ["Beam", "Apps", "People"].enumerated() {
            let tab = tabs.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "the \(title) tab is missing")
            tab.tap()
            pause(1.5)
            allowSystemPrompts(wait: 1)
            snapshot("p1\(index + 1)-companion-\(slug(title))")
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testB_whenHubSummaryArrives_thenHubTabDescribesIt() throws {
        launch(Hook.sample)
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 60))
        allowSystemPrompts(wait: 1)
        pause(1.5)
        snapshot("p20-companion-hub-summary")
        XCTAssertTrue(app.staticTexts["On the Hub"].exists || app.staticTexts["ON THE HUB"].exists, "the hub summary is missing")
    }

    /// On its side a phone is short, so each list is longer than the screen and starts with
    /// rows under the tab bar.
    func testC_whenPhoneOnItsSide_thenEachListScrollsClearOfTheTabBar() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        capturesLandscape = true
        pause(1)
        launch(Hook.sample)
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 60), "the companion's tab bar did not appear on its side")
        allowSystemPrompts(wait: 1)
        pause(1.5)
        snapshot("p30-landscape-companion-hub-summary")
        checkEndOfListClearsTabBar(app.staticTexts["Song"], snapshot: "p31-landscape-companion-hub-summary-at-the-end")
        tabs.buttons["Beam"].tap()
        pause(1.5)
        allowSystemPrompts(wait: 1)
        snapshot("p32-landscape-companion-beam")
        checkEndOfListClearsTabBar(app.buttons["Scan Pairing Code"], snapshot: "p33-landscape-companion-beam-at-the-end")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
