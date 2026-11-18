import XCTest

/// Shared plumbing for the screenshot walkthroughs: launching with test hooks, answering system
/// prompts, and saving a named screenshot of each stop.
@MainActor
class WalkthroughCase: XCTestCase {
    let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var notes: [String] = []

    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Set TEST_RUNNER_HOMEPAD_ORIENTATION=portrait to walk the hub upright. Those captures
    /// get "pt-" in front of their names.
    var isPortraitRun: Bool {
        ProcessInfo.processInfo.environment["HOMEPAD_ORIENTATION"] == "portrait"
    }

    /// Put in front of every screenshot name.
    var snapshotPrefix: String { "" }

    /// False where the app is framed smaller than the window, so the window's edges are not
    /// the hub's edges.
    var usesEdgeSwipes: Bool { true }

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
        /// Set on every launch: no Apple Intelligence gate in front of the app, and an
        /// assistant that answers from a script with no model, microphone, or speaker.
        static let always = ["HOMEPAD_UITEST_SKIP_AI_GATE": "1", "HOMEPAD_UITEST_SCRIPTED_ASSISTANT": "1"]
        static let square = ["HOMEPAD_UITEST_CANVAS": "square"]
        /// Stands in for Reduce Transparency, which a test cannot turn on.
        static let solidGlass = ["HOMEPAD_UITEST_SOLID_GLASS": "1"]
        static let assistant = ["HOMEPAD_UITEST_ASSISTANT": "1"]
        /// Runs the shell's animations this many times slower.
        static func slowMotion(_ factor: Int) -> [String: String] { ["HOMEPAD_UITEST_SLOW_MOTION": "\(factor)"] }
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
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(snapshotPrefix)notes-\(name.filter(\.isLetter)).txt")
        try? notes.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func launch(_ hooks: [String: String]...) {
        launch(hooks)
    }

    func launch(_ hooks: [[String: String]]) {
        app.terminate()
        app.launchEnvironment = hooks.reduce(into: Hook.always) { $0.merge($1) { _, new in new } }
        app.launch()
    }

    /// Closes the assistant, whichever one is filling the slot: the stand-in closes on a tap,
    /// and any assistant closes on a swipe up from the bottom edge.
    func closeAssistant() {
        let sample = element("assistant.sample")
        if sample.exists {
            sample.tap()
        } else {
            edgeSwipe(fromX: 0.5, fromY: 0.985, toX: 0.5, toY: 0.55)
        }
        pause(1.5)
        if element("hub.assistantOpen").exists {
            note("the assistant stayed open after it was asked to close")
        }
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
        let name = snapshotPrefix + name
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory = screenshotDirectory else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: url)
    }

    /// Swipes up from the bottom edge, the way a person gets to the Home Screen. The bar at the
    /// bottom is the fallback when the swipe is not taken.
    func openHomeScreen() {
        let home = app.scrollViews["hub.homeScreen"]
        if usesEdgeSwipes {
            edgeSwipe(fromX: 0.5, fromY: 0.985, toX: 0.5, toY: 0.55)
        }
        if !home.waitForExistence(timeout: usesEdgeSwipes ? 4 : 0.5) {
            if usesEdgeSwipes {
                note("the swipe up from the bottom edge did not open the Home Screen; used the bar")
            }
            app.buttons["hub.showHomeScreen"].firstMatch.tap()
        }
        XCTAssertTrue(home.waitForExistence(timeout: 8), "the Home Screen did not open")
        pause(1.5)
    }

    /// A drag between two points given as fractions of the app's window.
    func edgeSwipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: fromX, dy: fromY))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: toX, dy: toY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.05)
    }

    func tapWindow(x: CGFloat, y: CGFloat) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    }

    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
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
