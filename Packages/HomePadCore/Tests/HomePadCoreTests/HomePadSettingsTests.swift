import Foundation
import Testing
@testable import HomePadCore

@MainActor
@Suite struct HomePadSettingsTests {
    private static let flag = SettingKey<Bool>("test.flag", default: true)
    private static let name = SettingKey<String>("test.name", default: "fallback")
    private static let count = SettingKey<Int>("test.count", default: 3)
    private static let level = SettingKey<Double>("test.level", default: 0.5)

    private func makeDefaults() -> UserDefaults {
        let suite = "HomePadSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func subscript_whenUnset_thenReturnsKeyDefault() {
        let settings = HomePadSettings(defaults: makeDefaults())
        #expect(settings[Self.flag])
        #expect(settings[Self.name] == "fallback")
        #expect(settings[Self.count] == 3)
        #expect(settings[Self.level] == 0.5)
    }

    @Test func subscript_whenSet_thenReturnsStoredValue() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: Self.flag.name)
        defaults.set("stored", forKey: Self.name.name)
        defaults.set(9, forKey: Self.count.name)
        defaults.set(0.25, forKey: Self.level.name)
        let settings = HomePadSettings(defaults: defaults)
        #expect(!settings[Self.flag])
        #expect(settings[Self.name] == "stored")
        #expect(settings[Self.count] == 9)
        #expect(settings[Self.level] == 0.25)
    }

    @Test func register_whenDescriptorsGiven_thenRegistersEveryDefaultKind() {
        let defaults = makeDefaults()
        let settings = HomePadSettings(defaults: defaults)
        let options = [SettingDescriptor.Option(title: "One", value: "1")]
        settings.register([
            SettingDescriptor(SettingKey<Bool>("r.bool", default: true), title: "B", pane: "P", footer: "F"),
            SettingDescriptor(SettingKey<String>("r.choice", default: "1"), title: "C", pane: "P", options: options),
            SettingDescriptor(SettingKey<String>("r.text", default: "t"), title: "T", pane: "P"),
            SettingDescriptor(SettingKey<Int>("r.int", default: 4), title: "I", pane: "P", options: options),
            SettingDescriptor(SettingKey<Double>("r.double", default: 1.5), title: "D", pane: "P", minimum: 0, maximum: 2),
        ])
        #expect(defaults.bool(forKey: "r.bool"))
        #expect(defaults.string(forKey: "r.choice") == "1")
        #expect(defaults.string(forKey: "r.text") == "t")
        #expect(defaults.integer(forKey: "r.int") == 4)
        #expect(defaults.double(forKey: "r.double") == 1.5)
    }

    @Test func descriptorInitializers_whenBuilt_thenCarryControlAndDefault() {
        let options = [SettingDescriptor.Option(title: "One", value: "1")]
        let toggle = SettingDescriptor(Self.flag, title: "Flag", pane: "P", footer: "Footer")
        #expect(toggle.control == .toggle)
        #expect(toggle.defaultValue == .bool(true))
        #expect(toggle.footer == "Footer")
        #expect(SettingDescriptor(Self.name, title: "N", pane: "P", options: options).control == .choice(options))
        #expect(SettingDescriptor(Self.name, title: "N", pane: "P").control == .text)
        #expect(SettingDescriptor(Self.count, title: "C", pane: "P", options: options).defaultValue == .integer(3))
        #expect(SettingDescriptor(Self.level, title: "L", pane: "P", minimum: 0, maximum: 1).control == .slider(minimum: 0, maximum: 1))
    }

    @Test func didChangeNotification_whenPosted_thenObserversReRead() async {
        let defaults = makeDefaults()
        let center = NotificationCenter()
        let settings = HomePadSettings(defaults: defaults, notificationCenter: center)
        #expect(settings[Self.flag])

        let changed = AsyncStream<Void>.makeStream()
        withObservationTracking {
            _ = settings[Self.flag]
        } onChange: {
            changed.continuation.yield()
        }
        defaults.set(false, forKey: Self.flag.name)
        center.post(name: UserDefaults.didChangeNotification, object: defaults)

        var iterator = changed.stream.makeAsyncIterator()
        await iterator.next()
        #expect(!settings[Self.flag])
    }

    @Test func deinit_whenReleased_thenStopsObserving() {
        let center = NotificationCenter()
        let defaults = makeDefaults()
        var settings: HomePadSettings? = HomePadSettings(defaults: defaults, notificationCenter: center)
        settings?.refresh()
        settings = nil
        center.post(name: UserDefaults.didChangeNotification, object: defaults)
    }

    @Test func generalSettings_resolvedRole_coversOverridesAndAutomatic() {
        #expect(GeneralSettings.resolvedRole(setting: "hub", isPad: false) == .hub)
        #expect(GeneralSettings.resolvedRole(setting: "companion", isPad: true) == .companion)
        #expect(GeneralSettings.resolvedRole(setting: "automatic", isPad: true) == .hub)
        #expect(GeneralSettings.resolvedRole(setting: "anything else", isPad: false) == .companion)
        #expect(GeneralSettings.descriptors.map(\.name) == [
            "general.setupMode", "general.deviceRole", "general.requireCompanion", "general.staySignedInSeconds",
        ])
        #expect(GeneralSettings.descriptors.allSatisfy { $0.pane == GeneralSettings.pane })
    }

    @Test func generalSettings_lingerDuration_whenValueIsNotAChoice_thenDefault() throws {
        #expect(GeneralSettings.lingerDuration(setting: 0) == 0)
        #expect(GeneralSettings.lingerDuration(setting: 30) == 30)
        #expect(GeneralSettings.lingerDuration(setting: 600) == 600)
        #expect(GeneralSettings.lingerDuration(setting: 45) == 120)
        #expect(GeneralSettings.lingerDuration(setting: -1) == 120)
        #expect(GeneralSettings.lingerDuration(setting: GeneralSettings.staySignedInSeconds.defaultValue) == 120)

        let descriptor = try #require(GeneralSettings.descriptors.first { $0.name == GeneralSettings.staySignedInSeconds.name })
        #expect(descriptor.defaultValue == .integer(120))
        guard case .choice(let options) = descriptor.control else {
            Issue.record("expected a choice")
            return
        }
        #expect(options.map(\.value) == GeneralSettings.staySignedInOptions.map(String.init))
        #expect(options.map(\.title) == ["Off", "30 seconds", "2 minutes", "5 minutes", "10 minutes"])
    }
}
