import Foundation

/// Answers the recipe formatter's requests from fixed rules, with no language model: it finds
/// the recipe by its headings, moves a trailing amount to the front of an ingredient line, and
/// makes one short step of each sentence. For previews and UI tests on a machine with no
/// model. Its answers go through the same checks as a model's.
@MainActor
public final class ScriptedRecipeModel: RecipeModel {
    public let contextTokens: Int
    private let delay: Duration

    /// - Parameter delay: How long each answer takes, so that a reader can show its waiting state.
    public init(contextTokens: Int = RecipeLimits.fallbackContextTokens, delay: Duration = .zero) {
        self.contextTokens = contextTokens
        self.delay = delay
    }

    public func locate(_ request: RecipeModelRequest) async throws -> RecipeModelLocation {
        try await Task.sleep(for: delay)
        return Self.location(in: request.lines)
    }

    public func overview(_ request: RecipeModelRequest) async throws -> RecipeModelOverview {
        try await Task.sleep(for: delay)
        return RecipeModelOverview(
            summary: RecipeText.shortSummary(request.summary),
            ingredients: request.lines.map { RecipeModelLine(number: $0.number, text: Self.amountFirst($0.text)) }
        )
    }

    public func steps(_ request: RecipeModelRequest) async throws -> [RecipeModelStep] {
        try await Task.sleep(for: delay)
        return request.lines.flatMap { line in
            Self.parts(of: line.text).map { part in
                RecipeModelStep(
                    sourceStep: line.number,
                    title: Self.title(for: part),
                    instruction: part,
                    timerSeconds: RecipeScan(part).singleTimer ?? 0
                )
            }
        }
    }

    // MARK: Rules

    /// The ingredient list runs from the line after an ingredients heading to the line before
    /// a steps heading, and the steps from there to the end or to a notes heading.
    static func location(in lines: [RecipeModelLine]) -> RecipeModelLocation {
        let bare = lines.map { RecipePage.bare($0.text) }
        guard let ingredients = bare.firstIndex(where: RecipePage.ingredientHeadings.contains),
              let steps = bare[ingredients...].firstIndex(where: RecipePage.stepHeadings.contains) else {
            return RecipeModelLocation()
        }
        let end = bare[steps...].firstIndex(where: { ["notes", "tips", "nutrition"].contains(where: $0.hasPrefix) }) ?? bare.count
        let yield = bare.firstIndex(where: { ["serves", "servings", "makes", "yield"].contains(where: $0.hasPrefix) })
        return RecipeModelLocation(
            nameLine: ingredients > 0 ? 1 : 0,
            yieldLine: yield.map { $0 + 1 } ?? 0,
            firstIngredientLine: ingredients + 2,
            lastIngredientLine: steps,
            firstStepLine: steps + 2,
            lastStepLine: end
        )
    }

    /// "Flour, 2 cups" becomes "2 cups flour". Any other line stays as it is.
    static func amountFirst(_ line: String) -> String {
        guard let comma = line.lastIndex(of: ",") else { return line }
        let name = line[..<comma].trimmingCharacters(in: .whitespaces)
        let amount = line[line.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        guard RecipeScan(amount).startsWithMeasure, RecipeScan(name).quantities.isEmpty, !name.isEmpty else { return line }
        return "\(amount) \(name.prefix(1).lowercased())\(name.dropFirst())"
    }

    /// One part for each sentence. A step with more sentences than a step may have parts
    /// puts several sentences in a part.
    static func parts(of step: String) -> [String] {
        let sentences = RecipeText.sentences(step)
        let size = max(1, (sentences.count + RecipeLimits.maxPartsPerStep - 1) / RecipeLimits.maxPartsPerStep)
        return stride(from: 0, to: sentences.count, by: size).map { start in
            let text = sentences[start..<min(start + size, sentences.count)].joined(separator: " ")
            let ended = text.hasSuffix(";") ? String(text.dropLast()) + "." : text
            return ended.prefix(1).uppercased() + ended.dropFirst()
        }
    }

    private static let leadIns: Set<String> = ["in", "on", "using", "with", "meanwhile", "once", "when", "while", "after", "to", "for", "if"]
    private static let trailing: Set<String> = ["the", "a", "an", "to", "and", "with", "in", "of", "for", "until", "at", "into", "on", "or"]

    /// The first few words of the action: "Preheat the oven" for "Preheat the oven to 350
    /// degrees F." A sentence that opens with where or when starts after its first comma.
    static func title(for sentence: String) -> String {
        var words = sentence.split(separator: " ")
        if let first = words.first, leadIns.contains(first.lowercased()),
           let comma = words.firstIndex(where: { $0.hasSuffix(",") }), comma + 1 < words.count {
            words.removeSubrange(...comma)
        }
        var picked: [String] = []
        for word in words.prefix(4) {
            guard !word.contains(where: \.isNumber) else { break }
            picked.append(word.trimmingCharacters(in: .punctuationCharacters))
            guard word.last?.isPunctuation != true else { break }
        }
        while let last = picked.last, trailing.contains(last.lowercased()) {
            picked.removeLast()
        }
        let title = picked.joined(separator: " ")
        return title.prefix(1).uppercased() + title.dropFirst()
    }
}

/// Tidies recipes with `ScriptedRecipeModel`. What it returns passed the same checks as a
/// recipe the language model tidied.
@MainActor
public final class ScriptedRecipeFormatter: RecipeFormatting {
    private let formatter: RecipeFormatter

    public init(isEnabled: @escaping @MainActor () -> Bool = { true }, delay: Duration = .zero) {
        formatter = RecipeFormatter(model: ScriptedRecipeModel(delay: delay), isEnabled: isEnabled)
    }

    public func format(draft: RecipeDraft, pageText: String) async -> RecipeFormattingOutcome {
        await formatter.format(draft: draft, pageText: pageText)
    }
}

extension RecipeDraft {
    /// A recipe as a page's structured data gives it, for previews and UI tests.
    public static let sample = RecipeDraft(
        name: "Brown Butter Chocolate Chip Cookies",
        summary: "Chewy cookies with crisp edges and a deep, nutty flavor from browned butter. The dough rests for 30 minutes before baking.",
        yield: "24 cookies",
        totalTime: 3_300,
        ingredients: [
            "1 cup (2 sticks) unsalted butter",
            "1 cup packed dark brown sugar",
            "1/2 cup granulated sugar",
            "2 large eggs",
            "2 teaspoons vanilla extract",
            "2 1/4 cups all-purpose flour",
            "1 teaspoon baking soda",
            "3/4 teaspoon fine sea salt",
            "Chocolate chips, 2 cups",
        ],
        steps: [
            "Melt the butter in a light-colored saucepan over medium heat. Cook, swirling the pan often, until the butter foams and turns golden brown, 5 to 7 minutes. Pour the butter into a large bowl and let it cool for 10 minutes.",
            "Whisk the brown sugar and granulated sugar into the butter until smooth. Add the eggs and vanilla extract and whisk until glossy.",
            "In a medium bowl, stir together the flour, baking soda, and salt. Fold the flour mixture into the butter mixture until no dry streaks remain, then fold in the chocolate chips. Cover the dough and let it rest for 30 minutes.",
            "Preheat the oven to 375°F and line two baking sheets with parchment paper. Scoop the dough into 2-tablespoon balls and space them 2 inches apart.",
            "Bake until the edges are golden and the centers still look soft, 10 to 12 minutes. Let the cookies cool on the sheets for 5 minutes before moving them to a rack.",
        ]
    )
}
