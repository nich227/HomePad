import Foundation
import HomePadCore
import Testing
@testable import HomePadSettingsCatalog

@Suite struct SettingsBundleWriterTests {
    private let writer = SettingsBundleWriter(rootPane: "General")
    private let options = [
        SettingDescriptor.Option(title: "One", value: "1"),
        SettingDescriptor.Option(title: "Two", value: "2"),
    ]

    private func specifiers(_ list: [String: any Sendable]?) -> [[String: any Sendable]] {
        list?["PreferenceSpecifiers"] as? [[String: any Sendable]] ?? []
    }

    private func temporaryBundle() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/Settings.bundle")
    }

    @Test func propertyLists_whenEveryControlKind_thenEmitsMatchingSpecifiers() throws {
        let lists = try writer.propertyLists(for: [
            SettingDescriptor(SettingKey<Bool>("g.toggle", default: true), title: "Toggle", pane: "General"),
            SettingDescriptor(SettingKey<String>("g.text", default: "Kitchen"), title: "Text", pane: "General"),
            SettingDescriptor(SettingKey<String>("g.choice", default: "2"), title: "Choice", pane: "General", options: options),
            SettingDescriptor(SettingKey<Int>("g.number", default: 1), title: "Number", pane: "General", options: options),
            SettingDescriptor(SettingKey<Double>("g.slider", default: 0.5), title: "Slider", pane: "General", minimum: 0, maximum: 1),
        ])
        let rows = specifiers(lists["Root"])
        #expect(lists.count == 1)
        #expect(lists["Root"]?["StringsTable"] as? String == "Root")
        #expect(rows.map { $0["Type"] as? String } == [
            "PSGroupSpecifier", "PSToggleSwitchSpecifier", "PSTextFieldSpecifier",
            "PSMultiValueSpecifier", "PSMultiValueSpecifier", "PSSliderSpecifier",
        ])
        #expect(rows[1]["Key"] as? String == "g.toggle")
        #expect(rows[1]["DefaultValue"] as? Bool == true)
        #expect(rows[2]["DefaultValue"] as? String == "Kitchen")
        #expect(rows[3]["Values"] as? [String] == ["1", "2"])
        #expect(rows[3]["Titles"] as? [String] == ["One", "Two"])
        #expect(rows[4]["Values"] as? [Int] == [1, 2])
        #expect(rows[4]["DefaultValue"] as? Int == 1)
        #expect(rows[5]["MinimumValue"] as? Double == 0)
        #expect(rows[5]["MaximumValue"] as? Double == 1)
    }

    @Test func propertyLists_whenRowHasFooter_thenRowGetsItsOwnGroup() throws {
        let lists = try writer.propertyLists(for: [
            SettingDescriptor(SettingKey<Bool>("a", default: false), title: "A", pane: "General"),
            SettingDescriptor(SettingKey<Bool>("b", default: false), title: "B", pane: "General", footer: "About B"),
            SettingDescriptor(SettingKey<Bool>("c", default: false), title: "C", pane: "General"),
            SettingDescriptor(SettingKey<Bool>("d", default: false), title: "D", pane: "General"),
        ])
        let rows = specifiers(lists["Root"])
        #expect(rows.map { $0["Key"] as? String ?? "group" } == ["group", "a", "group", "b", "group", "c", "d"])
        #expect(rows[2]["FooterText"] as? String == "About B")
        #expect(rows[4]["FooterText"] == nil)
    }

    @Test func propertyLists_whenSeveralPanes_thenRootLinksToChildFiles() throws {
        let lists = try writer.propertyLists(for: [
            SettingDescriptor(SettingKey<Bool>("k", default: false), title: "K", pane: "Kiosk Lock"),
            SettingDescriptor(SettingKey<Bool>("g", default: false), title: "G", pane: "General"),
            SettingDescriptor(SettingKey<Bool>("m", default: false), title: "M", pane: "Messages & Projection"),
        ])
        let root = specifiers(lists["Root"])
        #expect(root.map { $0["Type"] as? String } == [
            "PSGroupSpecifier", "PSToggleSwitchSpecifier", "PSGroupSpecifier", "PSChildPaneSpecifier", "PSChildPaneSpecifier",
        ])
        #expect(root[3]["File"] as? String == "KioskLock")
        #expect(root[3]["Title"] as? String == "Kiosk Lock")
        #expect(root[4]["File"] as? String == "MessagesProjection")
        #expect(lists["KioskLock"]?["Title"] as? String == "Kiosk Lock")
        #expect(specifiers(lists["MessagesProjection"]).last?["Key"] as? String == "m")
        #expect(Set(lists.keys) == ["Root", "KioskLock", "MessagesProjection"])
    }

    @Test func propertyLists_whenNoRootPaneRows_thenRootOnlyLinks() throws {
        let lists = try writer.propertyLists(for: [
            SettingDescriptor(SettingKey<Bool>("k", default: false), title: "K", pane: "Kiosk Lock"),
        ])
        #expect(specifiers(lists["Root"]).map { $0["Type"] as? String } == ["PSGroupSpecifier", "PSChildPaneSpecifier"])
        #expect(try writer.propertyLists(for: []).keys.sorted() == ["Root"])
    }

    @Test func propertyLists_whenInvalid_thenThrowsTypedErrors() {
        let toggle = SettingDescriptor(SettingKey<Bool>("dup", default: false), title: "T", pane: "General")
        #expect(throws: SettingsBundleError.duplicateKey("dup")) { try writer.propertyLists(for: [toggle, toggle]) }
        #expect(throws: SettingsBundleError.choiceWithoutOptions("s")) {
            try writer.propertyLists(for: [SettingDescriptor(SettingKey<String>("s", default: "1"), title: "S", pane: "General", options: [])])
        }
        #expect(throws: SettingsBundleError.choiceWithoutOptions("i")) {
            try writer.propertyLists(for: [SettingDescriptor(SettingKey<Int>("i", default: 1), title: "I", pane: "General", options: [])])
        }
        #expect(throws: SettingsBundleError.defaultNotAmongOptions("s")) {
            try writer.propertyLists(for: [SettingDescriptor(SettingKey<String>("s", default: "9"), title: "S", pane: "General", options: options)])
        }
        #expect(throws: SettingsBundleError.defaultNotAmongOptions("i")) {
            try writer.propertyLists(for: [SettingDescriptor(SettingKey<Int>("i", default: 9), title: "I", pane: "General", options: options)])
        }
        #expect(throws: SettingsBundleError.nonNumericOption(key: "i", value: "x")) {
            try writer.propertyLists(for: [SettingDescriptor(SettingKey<Int>("i", default: 1), title: "I", pane: "General", options: [.init(title: "X", value: "x")])])
        }
        #expect(throws: SettingsBundleError.controlDoesNotMatchDefault("bad")) {
            try writer.propertyLists(for: [SettingDescriptor(name: "bad", title: "Bad", pane: "General", control: .toggle, defaultValue: .string("x"))])
        }
    }

    @Test func write_whenRun_thenFilesParseAndStaleOnesAreRemoved() throws {
        let bundle = temporaryBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let first = [
            SettingDescriptor(SettingKey<Bool>("g", default: true), title: "G", pane: "General"),
            SettingDescriptor(SettingKey<Bool>("k", default: false), title: "K", pane: "Kiosk Lock"),
        ]
        try writer.write(first, to: bundle)
        try Data("keep".utf8).write(to: bundle.appendingPathComponent("Root.strings"))
        #expect(try writer.staleFiles(for: first, in: bundle).isEmpty)

        let parsed = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: bundle.appendingPathComponent("KioskLock.plist")), format: nil
        ) as? [String: Any]
        #expect(parsed?["Title"] as? String == "Kiosk Lock")

        let second = [first[0]]
        #expect(try writer.staleFiles(for: second, in: bundle) == ["KioskLock.plist", "Root.plist"])
        try writer.write(second, to: bundle)
        let files = try FileManager.default.contentsOfDirectory(atPath: bundle.path).sorted()
        #expect(files == ["Root.plist", "Root.strings"])
        #expect(try writer.staleFiles(for: second, in: bundle).isEmpty)
    }

    @Test func staleFiles_whenBundleMissing_thenEveryFileIsStale() throws {
        let descriptors = [SettingDescriptor(SettingKey<Bool>("g", default: true), title: "G", pane: "General")]
        #expect(try writer.staleFiles(for: descriptors, in: temporaryBundle()) == ["Root.plist"])
    }
}
