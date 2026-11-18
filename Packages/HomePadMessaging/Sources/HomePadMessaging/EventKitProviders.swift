import EventKit
import Foundation
import HomePadMessagingCore
import UIKit

/// Shared EventKit plumbing for the Calendar and Reminders apps.
@MainActor
final class EventKitSource {
    let store = EKEventStore()
    private var observer: (any NSObjectProtocol)?

    func observeChanges(_ onChange: @escaping @MainActor () -> Void) {
        stopObserving()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { onChange() }
        }
    }

    func stopObserving() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    /// Shows the system prompt only while the app is in front; a prompt cannot appear from the background.
    func requestAccessIfUndetermined(to entity: EKEntityType) async {
        guard EKEventStore.authorizationStatus(for: entity) == .notDetermined,
              UIApplication.shared.applicationState == .active
        else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let completion: @Sendable (Bool, (any Error)?) -> Void = { _, _ in continuation.resume() }
            switch entity {
            case .reminder: store.requestFullAccessToReminders(completion: completion)
            default: store.requestFullAccessToEvents(completion: completion)
            }
        }
    }

    /// The screen to show instead of content, or `nil` when the app has full access.
    func accessTemplate(for entity: EKEntityType, id: String, title: String) -> ProjectionTemplate? {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .fullAccess:
            nil
        case .notDetermined:
            placeholderTemplate(id: id, title: title, message: String(localized: "Open HomePad on your iPhone to allow access."))
        default:
            placeholderTemplate(id: id, title: title, message: String(localized: "Access is off. Allow full access for HomePad in Settings on your iPhone."))
        }
    }
}

/// Today's and the coming week's events from the companion's calendars. Read only.
@MainActor
public final class CalendarAppProvider: ProjectedAppProvider {
    public let app = ProjectedApp(
        id: BuiltInProjectedApp.calendarID,
        name: String(localized: "Calendar"),
        symbolName: "calendar",
        tint: .red,
        category: .productivity,
        requiresPersonalContent: true
    )
    public let rootTemplateID = "calendar.root"

    private let source = EventKitSource()
    private let now: @Sendable () -> Date
    private let lookAhead: TimeInterval

    public init(lookAheadDays: Int = 7, now: @escaping @Sendable () -> Date = { Date() }) {
        self.lookAhead = TimeInterval(max(1, lookAheadDays)) * 24 * 60 * 60
        self.now = now
    }

    public func activate(onChange: @escaping @MainActor () -> Void) async {
        source.observeChanges(onChange)
        await source.requestAccessIfUndetermined(to: .event)
    }

    public func deactivate() {
        source.stopObserving()
    }

    public func launched() async {
        await source.requestAccessIfUndetermined(to: .event)
    }

    /// Asks for calendar access. Call from the companion's own UI while it is on screen.
    public func requestAccess() async {
        await source.requestAccessIfUndetermined(to: .event)
    }

    public func template(id: String) async -> ProjectionTemplate? {
        guard id == rootTemplateID else { return nil }
        if let blocked = source.accessTemplate(for: .event, id: rootTemplateID, title: app.name) {
            return blocked
        }
        let start = Calendar.current.startOfDay(for: now())
        let predicate = source.store.predicateForEvents(withStart: start, end: now().addingTimeInterval(lookAhead), calendars: nil)
        let items = source.store.events(matching: predicate).map { event in
            AgendaItem(
                id: event.calendarItemIdentifier,
                kind: .event,
                title: event.title ?? "",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                detail: event.location
            )
        }
        return AgendaProjection.template(
            id: rootTemplateID,
            title: app.name,
            emptyMessage: String(localized: "Nothing on your calendar this week."),
            items: items,
            untitled: String(localized: "Untitled Event"),
            now: now()
        )
    }

    public func handle(actionID: String, payload: [String: String]) async -> ProjectionNavigation {
        .none
    }
}

/// Open reminders that are overdue or due in the coming week, with completion from the hub.
@MainActor
public final class RemindersAppProvider: ProjectedAppProvider {
    public let app = ProjectedApp(
        id: BuiltInProjectedApp.remindersID,
        name: String(localized: "Reminders"),
        symbolName: "checklist",
        tint: .orange,
        category: .productivity,
        requiresPersonalContent: true
    )
    public let rootTemplateID = "reminders.root"

    private let source = EventKitSource()
    private let now: @Sendable () -> Date
    private let lookAhead: TimeInterval
    private var onChange: (@MainActor () -> Void)?
    /// Reminders completed from the hub stay listed, checked, so a mistaken tap can be undone.
    private var completedFromHub: [String: AgendaItem] = [:]

    public init(lookAheadDays: Int = 7, now: @escaping @Sendable () -> Date = { Date() }) {
        self.lookAhead = TimeInterval(max(1, lookAheadDays)) * 24 * 60 * 60
        self.now = now
    }

    public func activate(onChange: @escaping @MainActor () -> Void) async {
        self.onChange = onChange
        source.observeChanges(onChange)
        await source.requestAccessIfUndetermined(to: .reminder)
    }

    public func deactivate() {
        onChange = nil
        completedFromHub.removeAll()
        source.stopObserving()
    }

    public func launched() async {
        completedFromHub.removeAll()
        await source.requestAccessIfUndetermined(to: .reminder)
    }

    /// Asks for reminders access. Call from the companion's own UI while it is on screen.
    public func requestAccess() async {
        await source.requestAccessIfUndetermined(to: .reminder)
    }

    public func template(id: String) async -> ProjectionTemplate? {
        guard id == rootTemplateID else { return nil }
        if let blocked = source.accessTemplate(for: .reminder, id: rootTemplateID, title: app.name) {
            return blocked
        }
        var items = await openReminders()
        let openIDs = Set(items.map(\.id))
        items.append(contentsOf: completedFromHub.values.filter { !openIDs.contains($0.id) })
        return AgendaProjection.template(
            id: rootTemplateID,
            title: app.name,
            emptyMessage: String(localized: "No reminders due this week."),
            items: items,
            untitled: String(localized: "Untitled Reminder"),
            now: now()
        )
    }

    public func handle(actionID: String, payload: [String: String]) async -> ProjectionNavigation {
        guard let itemID = AgendaProjection.itemID(fromToggleActionID: actionID),
              EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
              let reminder = source.store.calendarItem(withIdentifier: itemID) as? EKReminder
        else { return .none }
        reminder.isCompleted.toggle()
        do {
            try source.store.save(reminder, commit: true)
        } catch {
            // The list is rebuilt from the store below, so a failed save shows the unchanged state.
            source.store.reset()
        }
        if reminder.isCompleted {
            completedFromHub[itemID] = Self.item(from: reminder)
        } else {
            completedFromHub[itemID] = nil
        }
        onChange?()
        return .none
    }

    private func openReminders() async -> [AgendaItem] {
        let predicate = source.store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: now().addingTimeInterval(lookAhead),
            calendars: nil
        )
        return await withCheckedContinuation { continuation in
            // Reminders are converted to values here because EventKit objects must not leave this callback's thread.
            _ = source.store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.item(from:)))
            }
        }
    }

    private nonisolated static func item(from reminder: EKReminder) -> AgendaItem {
        let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        return AgendaItem(
            id: reminder.calendarItemIdentifier,
            kind: .reminder,
            title: reminder.title ?? "",
            start: due,
            end: due,
            isAllDay: reminder.dueDateComponents?.hour == nil,
            detail: reminder.calendar?.title,
            isCompleted: reminder.isCompleted
        )
    }
}
