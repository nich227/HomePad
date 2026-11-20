import Foundation

/// A part of a page's readable text that fits one request to the model, reduced to the lines
/// that may hold the recipe. Line numbers the model answers with are positions in `lines`,
/// starting at one.
struct RecipePage: Equatable, Sendable {
    let lines: [String]
    /// True when the page has lines after this part.
    let wasCut: Bool

    /// Characters a line costs in a prompt beyond its own text: its number, brackets, and
    /// line break.
    static let lineOverhead = 6

    /// Cuts a page into parts that each fit `characterBudget`. A page that fits is one part.
    /// A longer one becomes parts that each start halfway through the one before, so that a
    /// recipe split by one cut is whole in the next part. At most `RecipeLimits.maxPageWindows`
    /// parts are made, and what lies past them is left out.
    /// - Parameter text: Plain text with one block of the page to a line.
    static func windows(_ text: String, characterBudget: Int) -> [RecipePage] {
        // A line that cannot fit any part is not a line of a recipe.
        let lines = candidateLines(text, characterBudget: characterBudget)
            .filter { $0.count + lineOverhead <= characterBudget }
        var windows: [RecipePage] = []
        var start = 0
        while start < lines.count, windows.count < RecipeLimits.maxPageWindows {
            var end = start
            var used = 0
            while end < lines.count, used + lines[end].count + lineOverhead <= characterBudget {
                used += lines[end].count + lineOverhead
                end += 1
            }
            windows.append(RecipePage(lines: Array(lines[start..<end]), wasCut: end < lines.count))
            guard end < lines.count else { break }
            start += max(1, (end - start) / 2)
        }
        return windows
    }

    /// The page's lines without menus, sharing buttons, comments, and, when room is short,
    /// the story above the recipe.
    private static func candidateLines(_ text: String, characterBudget: Int) -> [String] {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { RecipePrompt.sanitized(String($0)) }
            .filter { !$0.isEmpty && !boilerplate.contains(bare($0)) }
        guard let anchor = lines.firstIndex(where: { bare($0).hasPrefix("ingredients") }) else { return lines }
        // Comments and related links come after the recipe. Nothing below them is kept.
        let tail = lines[anchor...].firstIndex(where: isTailHeading) ?? lines.endIndex
        let body = lines[anchor..<tail]
        // Above the recipe, a line with a link, or one that shows up three times, is a menu
        // entry or a widget. From the ingredient list on, every line stays, because a
        // dropped line there could be an ingredient or a step.
        var counts: [String: Int] = [:]
        for line in lines[..<anchor] {
            counts[line.lowercased(), default: 0] += 1
        }
        let repeated = Set(counts.filter { $0.value >= 3 }.keys)
        var head = lines[..<anchor].filter { !repeated.contains($0.lowercased()) && !hasLink($0) }
        let size = (head + body).reduce(0) { $0 + $1.count + lineOverhead }
        if size > characterBudget {
            // The story above the recipe goes first. The top two lines stay for the name.
            head = Array(head.prefix(2))
        }
        return head + body
    }

    private static let boilerplate: Set<String> = [
        "advertisement", "skip to content", "skip to main content", "jump to recipe", "print recipe",
        "pin recipe", "save recipe", "rate this recipe", "share", "print", "pin", "save", "email",
        "subscribe", "sign up", "sign in", "log in", "menu", "search", "home", "privacy policy",
        "terms of use", "terms of service", "cookie policy", "all rights reserved", "follow us",
        "newsletter", "facebook", "twitter", "pinterest", "instagram", "youtube", "read more",
        "continue reading", "leave a comment", "leave a reply", "watch the video",
    ]

    /// A line in lowercase without the punctuation and symbols around it.
    static func bare(_ line: String) -> String {
        line.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted)
    }

    private static func hasLink(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return ["http:", "https:", "www.", "://", "\u{00A9}"].contains(where: lowered.contains)
    }

    private static func isTailHeading(_ line: String) -> Bool {
        let bare = bare(line)
        return ["comments", "reviews", "related", "you may also like", "you might also like", "more recipes", "about the author"]
            .contains(where: bare.hasPrefix)
    }

    /// Whether a line only names a section of the recipe, such as "Ingredients" or
    /// "Instructions:". Such a line is neither an ingredient nor a step.
    static func isSectionHeading(_ line: String) -> Bool {
        sectionHeadings.contains(bare(line))
    }

    static let ingredientHeadings: Set<String> = ["ingredients", "ingredient list", "what you need", "what you'll need"]
    static let stepHeadings: Set<String> = ["instructions", "directions", "method", "steps", "preparation", "how to make it"]
    private static let sectionHeadings = ingredientHeadings.union(stepHeadings)
}
