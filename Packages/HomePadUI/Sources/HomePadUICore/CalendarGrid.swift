import Foundation

/// The month grid of the Calendar face: six rows of seven days, including the trailing days of
/// the previous month and the leading days of the next.
public struct CalendarGrid: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public let date: Date
        public let number: Int
        public let isInMonth: Bool
        public let isToday: Bool

        public var id: Date { date }
    }

    public let monthStart: Date
    public let days: [Day]
    /// Calendar weekday numbers in column order, honoring the calendar's first weekday.
    public let weekdayOrder: [Int]

    public init(containing date: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: date)
        // Days are stepped from noon so a daylight saving shift never lands on the wrong date.
        let day: TimeInterval = 24 * 60 * 60
        let noonOfFirst = today.addingTimeInterval(day / 2 - Double(calendar.component(.day, from: today) - 1) * day)
        let monthStart = calendar.startOfDay(for: noonOfFirst)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        let month = calendar.component(.month, from: monthStart)
        self.monthStart = monthStart
        self.weekdayOrder = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        self.days = (0..<42).map { offset in
            let start = calendar.startOfDay(for: noonOfFirst.addingTimeInterval(Double(offset - lead) * day))
            return Day(
                date: start,
                number: calendar.component(.day, from: start),
                isInMonth: calendar.component(.month, from: start) == month,
                isToday: start == today
            )
        }
    }

    public var weeks: [[Day]] {
        stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }
}
