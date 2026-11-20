import Foundation

/// Text handling for recipes: what counts as plain text, where sentences end, and the labels
/// and bullets a page puts in front of its lines.
enum RecipeText {
    /// Whether text is free of markup, links, and addresses. Text a model wrote must pass this
    /// before it is shown.
    static func isPlain(_ text: String) -> Bool {
        let lowered = text.lowercased()
        guard !lowered.contains(where: { "<>[]{}|*#`@\\_".contains($0) }) else { return false }
        guard !["http:", "https:", "www.", "://"].contains(where: lowered.contains) else { return false }
        return lowered.firstMatch(of: #/\.(com|org|net|io|co|edu|gov|app|dev|info)\b/#) == nil
    }

    /// Splits at a period, question mark, exclamation mark, or semicolon that is followed by a
    /// space or the end. A period after a unit's abbreviation does not end a sentence.
    static func sentences(_ text: String) -> [String] {
        let characters = Array(text)
        var sentences: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            current.append(character)
            guard ".!?;".contains(character) else { continue }
            let endsHere = index + 1 == characters.count || characters[index + 1].isWhitespace
            guard endsHere, !(character == "." && endsWithAbbreviation(current.dropLast())) else { continue }
            sentences.append(current)
            current = ""
        }
        sentences.append(current)
        return sentences.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static let abbreviations: Set<String> = [
        "tbsp", "tbs", "tsp", "oz", "lb", "lbs", "min", "mins", "hr", "hrs", "sec", "secs",
        "fl", "pt", "qt", "gal", "pkg", "approx",
    ]

    private static func endsWithAbbreviation(_ text: Substring) -> Bool {
        let word = text.reversed().prefix(while: \.isLetter).reversed()
        return abbreviations.contains(String(word).lowercased())
    }

    /// Takes a step's label off the front of a line, such as "Step 2:" or "2.", and returns the
    /// number it carried.
    static func splitLabel(_ line: String) -> (number: Int?, text: String) {
        if let match = line.firstMatch(of: #/^step\s*(\d{1,2})\s*[:.)\-]?\s*/#.ignoresCase()), let number = Int(match.1) {
            return (number, String(line[match.range.upperBound...]))
        }
        if let match = line.firstMatch(of: #/^(\d{1,2})[.)](?:\s+|$)/#), let number = Int(match.1) {
            return (number, String(line[match.range.upperBound...]))
        }
        return (nil, line)
    }

    private static let bullets = CharacterSet(charactersIn: "-*\u{2022}\u{25A2}\u{25A1}\u{25E6}\u{00B7}\u{2013}\u{2014}\u{25AA}\u{2610}").union(.whitespaces)

    /// One line without the list bullet or check box a page draws in front of it.
    static func withoutBullet(_ line: String) -> String {
        let folded = AssistantText.singleLine(line, limit: .max)
        let scalars = folded.unicodeScalars.drop(while: bullets.contains)
        return String(String.UnicodeScalarView(scalars))
    }

    /// The first two sentences, cut to the summary's limit.
    static func shortSummary(_ text: String) -> String {
        AssistantText.clip(sentences(text).prefix(2).joined(separator: " "), limit: RecipeLimits.maxSummaryCharacters)
    }
}
