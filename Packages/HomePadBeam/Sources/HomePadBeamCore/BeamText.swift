import Foundation

/// Cleans text that arrives from another device before it is shown or stored.
public enum BeamText {
    public static let titleLimit = 200
    public static let deviceNameLimit = 40

    public static func sanitizedTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let cleaned = clean(title, limit: titleLimit)
        return cleaned.isEmpty ? nil : cleaned
    }

    public static func sanitizedDeviceName(_ name: String, fallback: String) -> String {
        let cleaned = clean(name, limit: deviceNameLimit)
        return cleaned.isEmpty ? fallback : cleaned
    }

    private static func clean(_ text: String, limit: Int) -> String {
        let scalars = text.unicodeScalars.map { scalar -> Character in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate:
                " "
            default:
                Character(scalar)
            }
        }
        let collapsed = String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return String(collapsed.prefix(limit))
    }
}
