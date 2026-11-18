import Foundation
@testable import HomePadUICore

enum Fixtures {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 1
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// Wednesday, April 1, 2026 at the given UTC time.
    static func date(day: Int = 1, hour: Int = 10, minute: Int = 9, second: Int = 0, month: Int = 4) -> Date {
        let components = DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second)
        return utc.date(from: components) ?? .distantPast
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("HomePadUICoreTests-\(UUID().uuidString)", isDirectory: true)
    }
}

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Fixtures.date()) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}
