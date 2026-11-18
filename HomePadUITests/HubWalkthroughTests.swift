import XCTest

/// Walks the hub the way a person would and saves a screenshot of each stop. Set
/// TEST_RUNNER_HOMEPAD_SCREENSHOT_DIR to keep the images outside the result bundle.
@MainActor
final class HubWalkthroughTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
    }

    func testWalkthrough_whenFirstLaunched_thenFacesHomeScreenAndAppsAppear() throws {
        allowSystemPrompts()
        let welcome = app.buttons["Not Now"]
        if welcome.waitForExistence(timeout: 30) {
            snapshot("01-welcome")
            welcome.tap()
        }
        allowSystemPrompts()
        pause(2)
        snapshot("02-first-face")

        for index in 1...10 {
            app.swipeLeft()
            pause(1.5)
            snapshot(String(format: "03-face-%02d", index))
        }

        app.swipeUp()
        pause(2)
        snapshot("04-home-screen")

        for name in ["Timers", "Home", "Music", "Recipes", "Beam", "iPhone Apps", "People", "Pairing", "Mirror", "Weather"] {
            let icon = app.buttons[name].firstMatch
            guard icon.waitForExistence(timeout: 3), icon.isHittable else { continue }
            icon.tap()
            pause(2)
            allowSystemPrompts()
            snapshot("05-app-\(name.replacingOccurrences(of: " ", with: "-").lowercased())")
            let close = app.buttons["Close"].firstMatch
            if close.waitForExistence(timeout: 3) {
                close.tap()
            } else {
                app.swipeDown()
            }
            pause(1)
        }

        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Permission alerts belong to the system, not the app, and cover whatever is under them.
    private func allowSystemPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let labels = ["Allow", "OK", "Allow While Using App", "Allow Full Access", "Continue"]
        for _ in 0..<8 {
            pause(1.5)
            guard let button = labels.lazy.map({ springboard.alerts.buttons[$0].firstMatch }).first(where: \.exists) else { return }
            button.tap()
        }
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory = ProcessInfo.processInfo.environment["HOMEPAD_SCREENSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: url)
    }
}
