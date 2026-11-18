import Foundation
import Testing
@testable import HomePadSettingsCatalog

private let bundleDirectory = ProcessInfo.processInfo.environment["HOMEPAD_SETTINGS_BUNDLE_DIR"]

/// Writes the Settings bundle the app ships. It runs only when HOMEPAD_SETTINGS_BUNDLE_DIR names
/// the bundle directory, which Scripts/generate-settings.sh does.
@Suite struct SettingsBundleGeneratorTests {
    @Test(.enabled(if: bundleDirectory != nil))
    func write_whenBundleDirectoryGiven_thenBundleMatchesTheCatalog() throws {
        let bundle = URL(fileURLWithPath: try #require(bundleDirectory), isDirectory: true)
        let writer = SettingsBundleWriter(rootPane: SettingsCatalog.rootPane)
        try writer.write(SettingsCatalog.descriptors, to: bundle)
        #expect(try writer.staleFiles(for: SettingsCatalog.descriptors, in: bundle).isEmpty)
    }
}
