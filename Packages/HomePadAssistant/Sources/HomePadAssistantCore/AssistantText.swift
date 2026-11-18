import Foundation

/// Text handling shared by prompt assembly, tool results, and answers.
public enum AssistantText {
    /// Folds text onto one line and cuts it to `limit` characters. Text from the hub and from
    /// people goes through here before it is placed in a prompt, so a line break inside it
    /// cannot pass for a new section of the prompt.
    public static func singleLine(_ text: String, limit: Int) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline || $0.unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains) })
        return clip(words.joined(separator: " "), limit: limit)
    }

    /// Cuts at the last word that fits and marks the cut.
    public static func clip(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let marker = "..."
        let head = text.prefix(max(0, limit - marker.count))
        guard let lastSpace = head.lastIndex(of: " ") else { return head + marker }
        return head[..<lastSpace] + marker
    }

    /// A length of time in words, to the two largest units.
    public static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let parts = [(total / 3600, "hour"), (total % 3600 / 60, "minute"), (total % 60, "second")]
            .filter { $0.0 > 0 }
            .prefix(2)
            .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }

    /// A temperature without a trailing ".0".
    public static func degrees(_ value: Double) -> String {
        let rounded = (value * 2).rounded() / 2
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}
