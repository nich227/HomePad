import Foundation
import HomePadCore
@testable import HomePadMessagingCore

enum Fixture {
    static let alice = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    static let bob = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
    static let phoneID = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
    static let otherPhoneID = UUID(uuidString: "22222222-0000-0000-0000-000000000002")!
    static let hubID = UUID(uuidString: "33333333-0000-0000-0000-000000000003")!
    static let hostSession = UUID(uuidString: "44444444-0000-0000-0000-000000000004")!
    static let hubSession = UUID(uuidString: "55555555-0000-0000-0000-000000000005")!
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static let phone = PeerDevice(id: phoneID, name: "Alice's iPhone", role: .companion, profileID: alice)
    static let otherPhone = PeerDevice(id: otherPhoneID, name: "Bob's iPhone", role: .companion, profileID: bob)
    static let hub = PeerDevice(id: hubID, name: "Kitchen", role: .hub)

    static let aliceVerified = ViewerContext(activeProfileID: alice, isPersonalContentUnlocked: true)
    static let aliceManual = ViewerContext(activeProfileID: alice, isPersonalContentUnlocked: false)
    static let bobVerified = ViewerContext(activeProfileID: bob, isPersonalContentUnlocked: true)

    static func app(_ id: String = "calendar", personal: Bool = true) -> ProjectedApp {
        ProjectedApp(id: id, name: id.capitalized, symbolName: "calendar", tint: .red, category: .productivity, requiresPersonalContent: personal)
    }

    static func row(_ id: String = "r1", title: String = "Row") -> ProjectionRow {
        ProjectionRow(id: id, title: title, subtitle: "Sub", symbolName: "star", accessory: .disclosure, actionID: "open.\(id)")
    }

    static func list(_ id: String = "root", title: String = "List", rows: [ProjectionRow]? = nil) -> ProjectionTemplate {
        .list(ListTemplate(id: id, title: title, sections: [ProjectionSection(id: "s1", header: "Header", rows: rows ?? [row()])], emptyMessage: "Nothing"))
    }

    static func hostFrame(_ message: HostToHubMessage, sequence: UInt64, session: UUID = hostSession) -> ProjectionFrame<HostToHubMessage> {
        ProjectionFrame(session: session, sequence: sequence, message: message)
    }

    static func hubFrame(_ message: HubToHostMessage, sequence: UInt64, session: UUID = hubSession) -> ProjectionFrame<HubToHostMessage> {
        ProjectionFrame(session: session, sequence: sequence, message: message)
    }

    static let allTemplates: [ProjectionTemplate] = [
        list(),
        .grid(GridTemplate(id: "grid", title: "Grid", buttons: [ProjectionButton(id: "b1", title: "Go", symbolName: "play", actionID: "go")])),
        .nowPlaying(NowPlayingTemplate(id: "np", title: "Song", artist: "Artist", album: "Album", artwork: Data([1, 2, 3]), elapsed: 10, duration: 100, isPlaying: true, commands: [.pause, .nextTrack])),
        .information(InformationTemplate(id: "info", title: "Info", items: [InformationItem(id: "i1", label: "Label", value: "Value")], buttons: [ProjectionButton(id: "b1", title: "Allow", actionID: "allow")])),
        .agenda(AgendaTemplate(id: "agenda", title: "Today", entries: [
            AgendaEntry(id: "e1", kind: .event, title: "Lunch", start: t0, end: t0.addingTimeInterval(3600), detail: "Cafe"),
            AgendaEntry(id: "r1", kind: .reminder, title: "Milk", actionID: "agenda.toggle.r1"),
        ], emptyMessage: "Nothing today")),
    ]
}

/// `#expect` cannot evaluate a call to a mutating method inline, so tests make the call through
/// this and compare the result.
func evaluated<Value>(_ body: () throws -> Value) rethrows -> Value {
    try body()
}
