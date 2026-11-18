import Foundation

public struct RecipeStep: Identifiable, Equatable, Sendable {
    /// Position in the whole recipe, starting at one.
    public let id: Int
    public let title: String?
    public let text: String
    /// A duration mentioned in the step, offered as a one-tap timer.
    public let timer: TimeInterval?
}

public struct RecipeSection: Equatable, Sendable {
    public let name: String?
    public let steps: [RecipeStep]
}

public struct Recipe: Equatable, Sendable {
    public let name: String
    public let summary: String?
    public let author: String?
    public let imageURL: URL?
    public let yield: String?
    public let prepTime: TimeInterval?
    public let cookTime: TimeInterval?
    public let totalTime: TimeInterval?
    public let ingredients: [String]
    public let sections: [RecipeSection]

    public var steps: [RecipeStep] { sections.flatMap(\.steps) }

    /// Total time when the page gives it, otherwise prep plus cook.
    public var displayDuration: TimeInterval? {
        if let totalTime { return totalTime }
        let sum = (prepTime ?? 0) + (cookTime ?? 0)
        return sum > 0 ? sum : nil
    }
}

public enum RecipeParseError: Error, Equatable, Sendable {
    case pageTooLarge
    /// The page has no structured data blocks at all.
    case noStructuredData
    /// The page has structured data, but none of it describes a recipe.
    case noRecipe
    /// A recipe was found but it has no name or no steps.
    case incompleteRecipe
}

/// Reads a schema.org Recipe out of a web page's JSON-LD. The page is treated as data only:
/// script blocks are parsed as JSON and never evaluated, and all text is reduced to plain text.
public enum RecipeParser {
    public static let maximumBytes = 4_000_000
    private static let maximumDepth = 12

    public static func parse(html: String) throws(RecipeParseError) -> Recipe {
        guard html.utf8.count <= maximumBytes else { throw .pageTooLarge }
        let blocks = jsonLDBlocks(in: html)
        guard !blocks.isEmpty else { throw .noStructuredData }
        var candidates: [[String: Any]] = []
        for block in blocks {
            guard let json = try? JSONSerialization.jsonObject(with: Data(block.utf8), options: [.fragmentsAllowed]) else { continue }
            collectRecipes(in: json, depth: 0, into: &candidates)
        }
        guard !candidates.isEmpty else { throw .noRecipe }
        guard let recipe = candidates.lazy.compactMap(build).first else { throw .incompleteRecipe }
        return recipe
    }

    static func jsonLDBlocks(in html: String) -> [String] {
        var blocks: [String] = []
        var cursor = html.startIndex
        while let open = html.range(of: "<script", options: .caseInsensitive, range: cursor..<html.endIndex) {
            guard let tagEnd = html.range(of: ">", range: open.upperBound..<html.endIndex) else { break }
            guard let close = html.range(of: "</script", options: .caseInsensitive, range: tagEnd.upperBound..<html.endIndex) else { break }
            if html[open.upperBound..<tagEnd.lowerBound].lowercased().contains("application/ld+json") {
                blocks.append(String(html[tagEnd.upperBound..<close.lowerBound]))
            }
            cursor = close.upperBound
        }
        return blocks
    }

    private static func collectRecipes(in value: Any, depth: Int, into result: inout [[String: Any]]) {
        guard depth < maximumDepth else { return }
        if let array = value as? [Any] {
            for element in array {
                collectRecipes(in: element, depth: depth + 1, into: &result)
            }
        } else if let object = value as? [String: Any] {
            if isType(object["@type"], "recipe") {
                result.append(object)
            }
            for key in ["@graph", "mainEntity", "mainEntityOfPage"] {
                if let nested = object[key] {
                    collectRecipes(in: nested, depth: depth + 1, into: &result)
                }
            }
        }
    }

    /// `@type` may be a string, an array, or a full schema.org URL.
    private static func isType(_ type: Any?, _ wanted: String) -> Bool {
        let names = (type as? [Any])?.compactMap { $0 as? String } ?? [type as? String].compactMap { $0 }
        return names.contains { name in
            let lowered = name.lowercased()
            return lowered == wanted || lowered.hasSuffix("/\(wanted)") || lowered.hasSuffix(":\(wanted)")
        }
    }

    private static func build(_ object: [String: Any]) -> Recipe? {
        var steps: [PendingStep] = []
        appendInstructions(object["recipeInstructions"], section: nil, depth: 0, into: &steps)
        guard let name = text(object["name"]) ?? text(object["headline"]), !steps.isEmpty else { return nil }
        return Recipe(
            name: name,
            summary: text(object["description"]),
            author: text(object["author"]),
            imageURL: imageURL(object["image"]),
            yield: yield(object["recipeYield"]),
            prepTime: duration(object["prepTime"]),
            cookTime: duration(object["cookTime"]),
            totalTime: duration(object["totalTime"]),
            ingredients: lines(object["recipeIngredient"] ?? object["ingredients"]),
            sections: sections(from: steps)
        )
    }

    private struct PendingStep {
        let section: String?
        let title: String?
        let text: String
    }

    private static func appendInstructions(_ value: Any?, section: String?, depth: Int, into steps: inout [PendingStep]) {
        guard depth < maximumDepth else { return }
        if let string = value as? String {
            for line in HTMLText.plain(string).split(separator: "\n") {
                let cleaned = HTMLText.strippingStepNumber(String(line))
                if !cleaned.isEmpty {
                    steps.append(PendingStep(section: section, title: nil, text: cleaned))
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                appendInstructions(element, section: section, depth: depth + 1, into: &steps)
            }
        } else if let object = value as? [String: Any] {
            if let nested = object["itemListElement"] {
                let name = isType(object["@type"], "howtosection") ? text(object["name"]) : nil
                appendInstructions(nested, section: name ?? section, depth: depth + 1, into: &steps)
            } else if let body = text(object["text"]) ?? text(object["description"]) ?? text(object["name"]) {
                let title = text(object["name"])
                let distinctTitle = title.flatMap { body.hasPrefix($0) ? nil : $0 }
                steps.append(PendingStep(section: section, title: distinctTitle, text: HTMLText.strippingStepNumber(body)))
            }
        }
    }

    private static func sections(from steps: [PendingStep]) -> [RecipeSection] {
        var sections: [RecipeSection] = []
        var current: [RecipeStep] = []
        var currentName: String?
        for (offset, step) in steps.enumerated() {
            if step.section != currentName, !current.isEmpty {
                sections.append(RecipeSection(name: currentName, steps: current))
                current = []
            }
            currentName = step.section
            current.append(RecipeStep(id: offset + 1, title: step.title, text: step.text, timer: RecipeTimers.duration(in: step.text)))
        }
        sections.append(RecipeSection(name: currentName, steps: current))
        return sections
    }

    /// The first usable string in a value that may be a string, a number, an array, or an object
    /// with a `name`, `text`, or `@value` member.
    private static func text(_ value: Any?) -> String? {
        if let string = value as? String {
            let cleaned = HTMLText.plain(string).replacingOccurrences(of: "\n", with: " ")
            return cleaned.isEmpty ? nil : cleaned
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let array = value as? [Any] {
            return array.lazy.compactMap { text($0) }.first
        }
        if let object = value as? [String: Any] {
            return text(object["name"]) ?? text(object["text"]) ?? text(object["@value"])
        }
        return nil
    }

    private static func lines(_ value: Any?) -> [String] {
        if let string = value as? String {
            return HTMLText.plain(string).split(separator: "\n").map(String.init)
        }
        return (value as? [Any] ?? []).compactMap { text($0) }
    }

    /// Sites often give both "4" and "4 servings". The one with words reads better.
    private static func yield(_ value: Any?) -> String? {
        let options = (value as? [Any])?.compactMap { text($0) } ?? [text(value)].compactMap { $0 }
        return options.first { $0.contains(where: \.isLetter) } ?? options.first
    }

    private static func imageURL(_ value: Any?) -> URL? {
        if let string = value as? String {
            return RecipeSourcePolicy.normalizedURL(from: string)
        }
        if let array = value as? [Any] {
            return array.lazy.compactMap { imageURL($0) }.first
        }
        if let object = value as? [String: Any] {
            return imageURL(object["url"] ?? object["contentUrl"])
        }
        return nil
    }

    private static func duration(_ value: Any?) -> TimeInterval? {
        guard let string = text(value) else { return nil }
        let seconds = ISO8601Duration.seconds(from: string) ?? RecipeTimers.duration(in: string)
        return seconds.flatMap { $0 > 0 ? $0 : nil }
    }
}

/// Which addresses the recipe reader will fetch or show images from.
public enum RecipeSourcePolicy {
    /// Accepts only web addresses. A bare host such as "example.com/soup" gets https.
    public static func normalizedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), host.contains(".") else { return nil }
        return url
    }
}

public enum ISO8601Duration {
    /// Seconds in a duration such as "PT1H30M" or "P1DT2H". Years and months have no fixed
    /// length and are rejected.
    public static func seconds(from text: String) -> TimeInterval? {
        let upper = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard upper.first == "P" else { return nil }
        var total: TimeInterval = 0
        var inTime = false
        var number = ""
        var components = 0
        for character in upper.dropFirst() {
            if character == "T" {
                guard number.isEmpty, !inTime else { return nil }
                inTime = true
                continue
            }
            if character.isASCII, character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
                continue
            }
            guard let value = Double(number), let unit = unitSeconds(character, inTime: inTime) else { return nil }
            total += value * unit
            number = ""
            components += 1
        }
        guard number.isEmpty, components > 0 else { return nil }
        return total
    }

    private static func unitSeconds(_ designator: Character, inTime: Bool) -> TimeInterval? {
        switch (designator, inTime) {
        case ("W", false): 604_800
        case ("D", false): 86_400
        case ("H", true): 3_600
        case ("M", true): 60
        case ("S", true): 1
        default: nil
        }
    }
}

public enum RecipeTimers {
    /// The first duration written in a step, for example "simmer for 1 hour 30 minutes" or
    /// "bake 25-30 min". A range uses its lower bound so the cook is prompted to check early.
    public static func duration(in text: String) -> TimeInterval? {
        let pattern = #/(\d+(?:\.\d+)?)(?:\s*(?:-|to)\s*\d+(?:\.\d+)?)?\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b/#.ignoresCase()
        var total: TimeInterval = 0
        var previousEnd: String.Index?
        for match in text.matches(of: pattern) {
            if let previousEnd {
                // "1 hour and 30 minutes" is one duration; anything else between matches starts a new one.
                let gap = text[previousEnd..<match.range.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
                guard gap.isEmpty || gap == "and" || gap == "," else { break }
            }
            let unit = match.output.2.lowercased()
            let multiplier: TimeInterval = unit.hasPrefix("h") ? 3_600 : unit.hasPrefix("m") ? 60 : 1
            if let value = Double(match.output.1) {
                total += value * multiplier
            }
            previousEnd = match.range.upperBound
        }
        guard total >= 1 else { return nil }
        return min(total, TimerEngine.maximumDuration)
    }
}

/// Turns markup fragments found in structured data into plain text.
public enum HTMLText {
    public static func plain(_ raw: String) -> String {
        var text = raw.replacing(#/<\s*(?:br|/p|/li|/div|/h[1-6])\b[^>]*>/#.ignoresCase(), with: "\n")
        text = text.replacing(#/<[^>]*>/#, with: "")
        text = decodingEntities(text)
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        text = text.replacingOccurrences(of: "\u{2013}", with: "-")
        text = text.replacingOccurrences(of: "\u{2014}", with: "-")
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Removes a leading "1." or "Step 2:" because the reader numbers steps itself.
    static func strippingStepNumber(_ text: String) -> String {
        text.replacing(#/^\s*(?:step\s*)?\d+\s*[.):]\s+/#.ignoresCase(), with: "")
    }

    static func decodingEntities(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let after = rest[rest.index(after: ampersand)...]
            if let semicolon = after.prefix(10).firstIndex(of: ";"), let decoded = entity(String(after[..<semicolon])) {
                result += decoded
                rest = after[after.index(after: semicolon)...]
            } else {
                result += "&"
                rest = after
            }
        }
        return result + rest
    }

    private static func entity(_ name: String) -> String? {
        guard name.hasPrefix("#") else { return namedEntities[name] }
        let digits = name.dropFirst()
        let isHex = digits.hasPrefix("x") || digits.hasPrefix("X")
        guard let value = isHex ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits),
              value >= 32, let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "deg": "\u{00B0}", "frac12": "\u{00BD}", "frac14": "\u{00BC}", "frac34": "\u{00BE}",
        "ndash": "-", "mdash": "-", "hellip": "...", "times": "\u{00D7}",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
        "eacute": "\u{00E9}", "egrave": "\u{00E8}", "agrave": "\u{00E0}", "ccedil": "\u{00E7}",
        "ntilde": "\u{00F1}", "uuml": "\u{00FC}", "ouml": "\u{00F6}", "auml": "\u{00E4}",
    ]
}
