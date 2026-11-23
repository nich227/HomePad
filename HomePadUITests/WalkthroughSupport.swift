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

    /// Set by a test that turns the device on its side, in case the device does not say so
    /// when a screenshot is saved.
    var capturesLandscape = false

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

    /// Types one request into the assistant and waits for its answer. The assistant answers
    /// from a script in UI tests.
    func askAssistant(_ request: String) {
        let field = app.textFields["assistant-field"]
        guard field.waitForExistence(timeout: 5) else {
            note("the assistant has no text field; it may be the stand-in")
            return
        }
        field.tap()
        field.typeText(request + "\n")
        if !element("assistant-answer").waitForExistence(timeout: 10) {
            note("the assistant did not answer \"\(request)\"")
        }
        pause(1.5)
    }

    /// Closes the assistant, whichever one is filling the slot: by its own close button, by a
    /// tap on the stand-in, or by a swipe up from the bottom edge.
    func closeAssistant() {
        let close = app.buttons["assistant-close"]
        let sample = element("assistant.sample")
        if close.exists {
            close.tap()
        } else if sample.exists {
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
        try? upright(screenshot.image).pngData()?.write(to: url)
    }

    /// The screen is captured the way the panel is mounted, so a landscape run gives pixels on
    /// their side, sometimes with a note of how to turn them and sometimes without. The saved
    /// file holds the pixels the way a person sees them.
    private func upright(_ image: UIImage) -> UIImage {
        // First apply whatever orientation the image carries.
        var flat = image
        if image.imageOrientation != .up {
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            format.opaque = true
            flat = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }
        let orientation = XCUIDevice.shared.orientation
        guard orientation.isLandscape || capturesLandscape, flat.size.height > flat.size.width else { return flat }
        // Still on its side: turn it.
        let size = CGSize(width: flat.size.height, height: flat.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = flat.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: orientation == .landscapeRight ? .pi / 2 : -.pi / 2)
            flat.draw(in: CGRect(x: -flat.size.width / 2, y: -flat.size.height / 2, width: flat.size.width, height: flat.size.height))
        }
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

    /// A tab bar floats over the list behind it, so a long list starts with rows under the
    /// bar. Scrolls that list to its end, saves a screenshot, and checks that the element
    /// named last then sits above the bar, where it can be read and tapped.
    func checkEndOfListClearsTabBar(_ last: XCUIElement, snapshot name: String) {
        let bar = app.tabBars.firstMatch
        func barTop() -> CGFloat {
            bar.buttons.allElementsBoundByIndex.map(\.frame.minY).min() ?? bar.frame.minY
        }
        let top = barTop()
        note("\(name), before scrolling: tab bar \(bar.frame), its buttons from y \(top), last row \(last.exists ? "\(last.frame)" : "not loaded yet")")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<2 {
            let start = origin.withOffset(CGVector(dx: bar.frame.midX, dy: top - 30))
            let end = origin.withOffset(CGVector(dx: bar.frame.midX, dy: top - 250))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.3)
            pause(1)
        }
        snapshot(name)
        guard last.waitForExistence(timeout: 3) else {
            note("\(name): the last row is missing after scrolling to the end")
            XCTFail("\(name): the last row is missing after scrolling to the end")
            return
        }
        note("\(name), at the end: its buttons from y \(barTop()), last row \(last.frame)")
        XCTAssertLessThanOrEqual(last.frame.maxY, barTop() + 0.5, "\(name): the end of the list stays under the tab bar")
    }

    func slug(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
