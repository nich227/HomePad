import Foundation
import HomePadCore

public enum SettingsBundleError: Error, Equatable, Sendable {
    case duplicateKey(String)
    case choiceWithoutOptions(String)
    case defaultNotAmongOptions(String)
    case nonNumericOption(key: String, value: String)
    case controlDoesNotMatchDefault(String)
}

/// Turns setting descriptors into the property lists of a Settings bundle: `Root.plist` holds the
/// first pane's rows and one link per further pane, and each further pane gets its own file.
public struct SettingsBundleWriter: Sendable {
    public let rootPane: String

    public init(rootPane: String) {
        self.rootPane = rootPane
    }

    /// File name (without extension) to property list.
    public func propertyLists(for descriptors: [SettingDescriptor]) throws -> [String: [String: any Sendable]] {
        try validate(descriptors)
        var paneOrder: [String] = []
        var byPane: [String: [SettingDescriptor]] = [:]
        for descriptor in descriptors {
            if byPane[descriptor.pane] == nil { paneOrder.append(descriptor.pane) }
            byPane[descriptor.pane, default: []].append(descriptor)
        }

        var files: [String: [String: any Sendable]] = [:]
        var root = try specifiers(for: byPane[rootPane] ?? [])
        let childPanes = paneOrder.filter { $0 != rootPane }
        if !childPanes.isEmpty {
            root.append(["Type": "PSGroupSpecifier"])
        }
        for pane in childPanes {
            let file = Self.fileName(for: pane)
            root.append(["Type": "PSChildPaneSpecifier", "Title": pane, "File": file])
            files[file] = [
                "Title": pane,
                "StringsTable": file,
                "PreferenceSpecifiers": try specifiers(for: byPane[pane] ?? []),
            ]
        }
        files["Root"] = ["StringsTable": "Root", "PreferenceSpecifiers": root]
        return files
    }

    public func write(_ descriptors: [SettingDescriptor], to bundle: URL, fileManager: FileManager = .default) throws {
        let lists = try propertyLists(for: descriptors)
        try fileManager.createDirectory(at: bundle, withIntermediateDirectories: true)
        let existing = try fileManager.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil)
        for stale in existing where stale.pathExtension == "plist" && lists[stale.deletingPathExtension().lastPathComponent] == nil {
            try fileManager.removeItem(at: stale)
        }
        for (name, list) in lists {
            try Self.data(for: list).write(to: bundle.appendingPathComponent("\(name).plist"), options: .atomic)
        }
    }

    /// Names of the files whose contents on disk differ from what the descriptors produce.
    public func staleFiles(for descriptors: [SettingDescriptor], in bundle: URL) throws -> [String] {
        let lists = try propertyLists(for: descriptors)
        var stale: [String] = []
        for (name, list) in lists {
            let onDisk = try? Data(contentsOf: bundle.appendingPathComponent("\(name).plist"))
            if try onDisk != Self.data(for: list) { stale.append("\(name).plist") }
        }
        let known = Set(lists.keys)
        let present = (try? FileManager.default.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil)) ?? []
        for file in present where file.pathExtension == "plist" && !known.contains(file.deletingPathExtension().lastPathComponent) {
            stale.append(file.lastPathComponent)
        }
        return stale.sorted()
    }

    static func data(for list: [String: any Sendable]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: list, format: .xml, options: 0)
    }

    static func fileName(for pane: String) -> String {
        pane.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private func validate(_ descriptors: [SettingDescriptor]) throws {
        var seen: Set<String> = []
        for descriptor in descriptors {
            guard seen.insert(descriptor.name).inserted else { throw SettingsBundleError.duplicateKey(descriptor.name) }
        }
    }

    /// A row with a footer gets a group of its own, because Settings draws a footer under the
    /// whole group and it would otherwise read as describing the rows next to it.
    private func specifiers(for descriptors: [SettingDescriptor]) throws -> [[String: any Sendable]] {
        var result: [[String: any Sendable]] = []
        var groupIsOpen = false
        for descriptor in descriptors {
            if let footer = descriptor.footer {
                result.append(["Type": "PSGroupSpecifier", "FooterText": footer])
                groupIsOpen = false
            } else if !groupIsOpen {
                result.append(["Type": "PSGroupSpecifier"])
                groupIsOpen = true
            }
            result.append(try row(for: descriptor))
        }
        return result
    }

    private func row(for descriptor: SettingDescriptor) throws -> [String: any Sendable] {
        var row: [String: any Sendable] = ["Key": descriptor.name, "Title": descriptor.title]
        switch (descriptor.control, descriptor.defaultValue) {
        case (.toggle, .bool(let value)):
            row["Type"] = "PSToggleSwitchSpecifier"
            row["DefaultValue"] = value

        case (.text, .string(let value)):
            row["Type"] = "PSTextFieldSpecifier"
            row["DefaultValue"] = value
            row["AutocapitalizationType"] = "Words"
            row["AutocorrectionType"] = "No"

        case (.slider(let minimum, let maximum), .number(let value)):
            row["Type"] = "PSSliderSpecifier"
            row["DefaultValue"] = value
            row["MinimumValue"] = minimum
            row["MaximumValue"] = maximum

        case (.choice(let options), .string(let value)):
            guard !options.isEmpty else { throw SettingsBundleError.choiceWithoutOptions(descriptor.name) }
            guard options.contains(where: { $0.value == value }) else {
                throw SettingsBundleError.defaultNotAmongOptions(descriptor.name)
            }
            row["Type"] = "PSMultiValueSpecifier"
            row["DefaultValue"] = value
            row["Titles"] = options.map(\.title)
            row["Values"] = options.map(\.value)

        case (.choice(let options), .integer(let value)):
            guard !options.isEmpty else { throw SettingsBundleError.choiceWithoutOptions(descriptor.name) }
            let values = try options.map { option -> Int in
                guard let number = Int(option.value) else {
                    throw SettingsBundleError.nonNumericOption(key: descriptor.name, value: option.value)
                }
                return number
            }
            guard values.contains(value) else { throw SettingsBundleError.defaultNotAmongOptions(descriptor.name) }
            row["Type"] = "PSMultiValueSpecifier"
            row["DefaultValue"] = value
            row["Titles"] = options.map(\.title)
            row["Values"] = values

        default:
            throw SettingsBundleError.controlDoesNotMatchDefault(descriptor.name)
        }
        return row
    }
}
