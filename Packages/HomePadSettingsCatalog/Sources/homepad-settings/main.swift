import Foundation
import HomePadSettingsCatalog

// Writes the Settings bundle plists from the setting descriptors, or with --check reports
// whether the checked-in plists are current.
let arguments = Array(CommandLine.arguments.dropFirst())
guard let path = arguments.first(where: { !$0.hasPrefix("--") }) else {
    FileHandle.standardError.write(Data("usage: homepad-settings <Settings.bundle> [--check]\n".utf8))
    exit(2)
}
let bundle = URL(fileURLWithPath: path)
let writer = SettingsBundleWriter(rootPane: SettingsCatalog.rootPane)

do {
    if arguments.contains("--check") {
        let stale = try writer.staleFiles(for: SettingsCatalog.descriptors, in: bundle)
        guard stale.isEmpty else {
            print("out of date: \(stale.joined(separator: ", "))")
            exit(1)
        }
        print("Settings bundle is current (\(SettingsCatalog.descriptors.count) settings).")
    } else {
        try writer.write(SettingsCatalog.descriptors, to: bundle)
        print("wrote \(SettingsCatalog.descriptors.count) settings to \(bundle.path)")
    }
} catch {
    FileHandle.standardError.write(Data("homepad-settings: \(error)\n".utf8))
    exit(1)
}
