import XCTest

/// Shared plumbing for the screenshot walkthroughs: launching with test hooks, answering system
/// prompts, and saving a named screenshot of each stop.
@MainActor
class WalkthroughCase: XCTestCase {
    let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var notes: [String] = []

    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// The small iPad stands in for a folding iPhone, whose displays this machine cannot
    /// simulate. Its screen is large enough to frame both of them.
    var isDuoStandIn: Bool {
        let bounds = UIScreen.main.bounds
        return isPad && min(bounds.width, bounds.height) < 800
    }

    /// The app reads these only in debug builds. None is set in normal use.
    enum Hook {
        static let ephemeral = ["HOMEPAD_UITEST_EPHEMERAL": "1"]
        static let sample = ["HOMEPAD_UITEST_SAMPLE": "1"]
        static func audience(_ value: String) -> [String: String] { ["HOMEPAD_UITEST_AUDIENCE": value] }
        static func proximity(_ value: String) -> [String: String] { ["HOMEPAD_UITEST_PROXIMITY": value] }
        static let fill = ["HOMEPAD_UITEST_CANVAS": "fill"]
        static let night = ["HOMEPAD_UITEST_NIGHT": "1"]
        static let deviceUnlock = ["HOMEPAD_UITEST_DEVICE_UNLOCK": "1"]
        static let skipWelcome = ["HOMEPAD_UITEST_SKIP_WELCOME": "1"]
        static let fold = ["HOMEPAD_UITEST_FOLD": "1"]
        static func role(_ value: String) -> [String: String] { ["HOMEPAD_UITEST_ROLE": value] }
        /// Frames the whole app to a size in points, for example "626x890".
        static func viewport(_ value: String) -> [String: String] { ["HOMEPAD_UITEST_VIEWPORT": value] }
    }

    override func setUp() async throws {
        continueAfterFailure = true
    }

    override func tearDown() async throws {
        app.terminate()
        guard !notes.isEmpty, let directory = screenshotDirectory else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("notes-\(name.filter(\.isLetter)).txt")
        try? notes.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func launch(_ hooks: [String: String]...) {
        app.terminate()
        app.launchEnvironment = hooks.reduce(into: [:]) { $0.merge($1) { _, new in new } }
        app.launch()
    }

    func note(_ text: String) {
        notes.append(text)
    }

    func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    var isSystemPromptShowing: Bool {
        springboard.alerts.firstMatch.exists
    }

    /// Permission alerts belong to the system, not the app, and cover whatever is under them.
    @discardableResult
    func allowSystemPrompts(wait: TimeInterval = 1.5) -> Int {
        let labels = ["Allow", "OK", "Allow While Using App", "Allow Full Access", "Continue"]
        var answered = 0
        for _ in 0..<6 {
            guard springboard.alerts.firstMatch.waitForExistence(timeout: wait) else { break }
            guard let button = labels.lazy.map({ self.springboard.alerts.buttons[$0].firstMatch }).first(where: \.exists) else { break }
            button.tap()
            answered += 1
            pause(0.8)
        }
        return answered
    }

    private var screenshotDirectory: String? {
        ProcessInfo.processInfo.environment["HOMEPAD_SCREENSHOT_DIR"]
    }

    func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory = screenshotDirectory else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: url)
    }

    func openHomeScreen() {
        let button = app.buttons["hub.showHomeScreen"]
        if button.waitForExistence(timeout: 5), button.isHittable {
            button.tap()
        } else {
            app.swipeUp()
        }
        XCTAssertTrue(app.scrollViews["hub.homeScreen"].waitForExistence(timeout: 8), "the Home Screen did not open")
        pause(1.5)
    }

    /// Finds an icon on the Home Screen, scrolling if it is below the fold, and taps it.
    func tapApp(_ id: String) -> Bool {
        let icon = app.buttons["app.\(id)"]
        let scroll = app.scrollViews["hub.homeScreen"]
        guard icon.waitForExistence(timeout: 4) else {
            note("icon \(id) is not on the Home Screen")
            XCTFail("icon \(id) is not on the Home Screen")
            return false
        }
        for _ in 0..<4 where !icon.isHittable {
            scroll.swipeUp(velocity: .slow)
            pause(0.8)
        }
        guard icon.isHittable else {
            note("icon \(id) could not be reached by scrolling")
            XCTFail("icon \(id) could not be reached by scrolling")
            return false
        }
        icon.tap()
        pause(2)
        if allowSystemPrompts(wait: 1) > 0 {
            note("a prompt was answered when \(id) opened")
        }
        return true
    }

    func slug(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
