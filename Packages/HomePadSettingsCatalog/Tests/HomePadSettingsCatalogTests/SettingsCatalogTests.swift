import Foundation
import HomePadCore
import Testing
@testable import HomePadSettingsCatalog

@Suite struct SettingsCatalogTests {
    @Test func descriptors_whenWritten_thenFormAValidSettingsBundle() throws {
        let lists = try SettingsBundleWriter(rootPane: SettingsCatalog.rootPane).propertyLists(for: SettingsCatalog.descriptors)
        let panes = Set(SettingsCatalog.descriptors.map(\.pane))
        #expect(panes.contains(SettingsCatalog.rootPane))
        #expect(lists.count == panes.count)
        for list in lists.values {
            _ = try SettingsBundleWriter.data(for: list)
        }
    }

    @Test func descriptors_whenListed_thenNamesAreUniqueAndPrefixedByFeature() {
        let names = SettingsCatalog.descriptors.map(\.name)
        #expect(Set(names).count == names.count)
        let prefixes = Set(names.compactMap { $0.split(separator: ".").first.map(String.init) })
        #expect(prefixes == ["general", "kiosk", "face", "beam", "messaging", "ui"])
        #expect(SettingsCatalog.descriptors.allSatisfy { !$0.title.isEmpty && !$0.pane.isEmpty })
    }

    @Test func sharedWithExtensions_whenListed_thenEveryKeyIsACatalogSetting() {
        let names = Set(SettingsCatalog.descriptors.map(\.name))
        #expect(!SettingsCatalog.sharedWithExtensions.isEmpty)
        #expect(SettingsCatalog.sharedWithExtensions.allSatisfy(names.contains))
    }

    @Test func checkedInBundle_whenCompared_thenMatchesTheCatalog() throws {
        let bundle = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HomePad/Settings.bundle")
        let stale = try SettingsBundleWriter(rootPane: SettingsCatalog.rootPane)
            .staleFiles(for: SettingsCatalog.descriptors, in: bundle)
        #expect(stale.isEmpty, "Run Scripts/generate-settings.sh to refresh \(stale)")
    }
}
