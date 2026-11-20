import Foundation

/// One short step that passed every check against the page's step it came from.
struct RecipeCheckedPart: Equatable, Sendable {
    let title: String
    let instruction: String
    let timerSeconds: Int?
}

/// Checks what a model wrote against the page's own recipe. Nothing a model wrote reaches a
/// `FormattedRecipe` without passing here. Each check returns nil for text that must not be
/// shown, and the caller then keeps the page's text.
///
/// Two texts agree on an amount when the number and the unit are the same, however they are
/// spelled: "1/2", "½", and "0.5"; "1 1/2", "1½", and "1.5"; "2" and "two"; "a cup" and "1 cup";
/// "10 minutes" and "10 min"; "350°F", "350 degrees F", and "350 F". A conversion is not the
/// same amount: "1 hour" and "60 minutes" differ, and so do "350 degrees" and "350°F".
enum RecipeValidator {
    /// Folds text a model wrote onto one line and refuses it when it is empty, too long, or
    /// holds markup, a link, or an address.
    static func plainText(_ text: String, limit: Int) -> String? {
        let folded = AssistantText.singleLine(text, limit: .max)
        guard !folded.isEmpty, folded.count <= limit, RecipeText.isPlain(folded) else { return nil }
        return folded
    }

    // MARK: Ingredients

    /// A rewritten ingredient line may only reorder the page's line: the same amounts, each as
    /// many times, and the same words.
    static func ingredientLine(_ candidate: String, source: String) -> String? {
        guard let line = plainText(candidate, limit: RecipeLimits.maxIngredientCharacters) else { return nil }
        let written = RecipeScan(line)
        let original = RecipeScan(source)
        guard written.requiredCounts == original.requiredCounts else { return nil }
        guard Set(written.words) == Set(original.words) else { return nil }
        return line
    }

    /// The rewritten lines that passed, by the number of the line each rewrites. A number the
    /// model was not sent, or one it answered twice, gives nothing.
    static func ingredientLines(_ answer: [RecipeModelLine], request: RecipeModelRequest) -> [Int: String] {
        var result: [Int: String] = [:]
        var seen: Set<Int> = []
        for line in answer {
            guard seen.insert(line.number).inserted else {
                result[line.number] = nil
                continue
            }
            guard let source = request.lines.first(where: { $0.number == line.number }) else { continue }
            result[line.number] = ingredientLine(line.text, source: source.text)
        }
        return result
    }

    /// A summary may use only amounts the recipe states, and most of its words must be the
    /// recipe's own.
    static func summary(_ candidate: String, recipe: RecipeDraft) -> String? {
        guard let summary = plainText(candidate, limit: RecipeLimits.maxSummaryCharacters) else { return nil }
        guard RecipeText.sentences(summary).count <= 2 else { return nil }
        let written = RecipeScan(summary)
        let source = RecipeScan(([recipe.name, recipe.summary] + recipe.ingredients).joined(separator: ". "))
        guard Set(written.required.map(\.key)).isSubset(of: source.allKeys) else { return nil }
        let known = Set(source.words)
        let matched = written.words.filter(known.contains).count
        guard !written.words.isEmpty, Double(matched) >= RecipeLimits.summaryPrecision * Double(written.words.count) else { return nil }
        return summary
    }

    // MARK: Steps

    /// The short steps the model wrote for each of the page's steps, for the steps whose
    /// short steps passed. The whole answer is refused when it names a step it was not sent
    /// or goes back to an earlier step: an answer that reorders cannot be trusted in part.
    /// - Parameter vocabulary: The words that name the recipe's ingredients.
    static func steps(_ answer: [RecipeModelStep], request: RecipeModelRequest, vocabulary: Set<String>) -> [Int: [RecipeCheckedPart]] {
        let numbers = answer.map(\.sourceStep)
        guard numbers == numbers.sorted() else { return [:] }
        guard Set(numbers).isSubset(of: Set(request.lines.map(\.number))) else { return [:] }
        var result: [Int: [RecipeCheckedPart]] = [:]
        for line in request.lines {
            let parts = answer.filter { $0.sourceStep == line.number }
            result[line.number] = step(parts, source: line.text, vocabulary: vocabulary)
        }
        return result
    }

    /// Checks the short steps written for one of the page's steps.
    static func step(_ parts: [RecipeModelStep], source: String, vocabulary: Set<String>) -> [RecipeCheckedPart]? {
        guard (1...RecipeLimits.maxPartsPerStep).contains(parts.count) else { return nil }
        var instructions: [String] = []
        for part in parts {
            guard let instruction = plainText(part.instruction, limit: RecipeLimits.maxInstructionCharacters),
                  RecipeText.sentences(instruction).count <= RecipeLimits.maxInstructionSentences else { return nil }
            instructions.append(instruction)
        }
        let original = RecipeScan(source)
        let written = instructions.map(RecipeScan.init)
        guard amountsAgree(written: written, original: original) else { return nil }
        let writtenWords = Set(written.flatMap(\.words))
        let originalWords = Set(original.words)
        // No word the page's step does not have, so no ingredient or technique is added.
        guard writtenWords.isSubset(of: originalWords.union(RecipeWords.neutralVerbs)) else { return nil }
        // Every ingredient the step names stays, and so does every word that reverses or
        // orders what the cook does.
        let mustKeep = originalWords.intersection(vocabulary.union(RecipeWords.protected))
        guard mustKeep.isSubset(of: writtenWords) else { return nil }
        // No sentence of the step is dropped.
        for sentence in RecipeText.sentences(source) {
            let words = RecipeScan(sentence).words
            let kept = words.filter(writtenWords.contains).count
            guard Double(kept) >= RecipeLimits.sentenceRecall * Double(words.count) else { return nil }
        }
        return zip(parts, zip(instructions, written)).map { part, text in
            RecipeCheckedPart(
                title: title(part.title, instruction: text.1, allowed: originalWords),
                instruction: text.0,
                timerSeconds: timer(part.timerSeconds, instruction: text.1)
            )
        }
    }

    /// The short steps must state the page's amounts once each and in the page's order, and
    /// each amount must still measure the same thing.
    static func amountsAgree(written: [RecipeScan], original: RecipeScan) -> Bool {
        let writtenAmounts = written.flatMap { scan in scan.required.map { (scan: scan, quantity: $0) } }
        let originalAmounts = original.required
        guard writtenAmounts.map(\.quantity.key) == originalAmounts.map(\.key) else { return false }
        for (new, old) in zip(writtenAmounts, originalAmounts) {
            let now = new.scan.context(of: new.quantity)
            let then = original.context(of: old)
            let after = comparison(now.after, then.after)
            if old.unit?.measuresFood ?? true {
                // An amount of food is followed by the food: "1 cup flour".
                guard after != .differs else { return false }
            } else {
                // A time or a temperature belongs to the action around it: "bake 10 minutes".
                let before = comparison(now.before, then.before)
                guard after == .shares || before == .shares || (after == .unknown && before == .unknown) else { return false }
            }
        }
        return true
    }

    private enum Comparison {
        case shares, differs, unknown
    }

    private static func comparison(_ first: Set<String>, _ second: Set<String>) -> Comparison {
        guard !first.isEmpty, !second.isEmpty else { return .unknown }
        return first.isDisjoint(with: second) ? .differs : .shares
    }

    /// A title that fails gives an empty title. The step itself stays.
    static func title(_ candidate: String, instruction: RecipeScan, allowed: Set<String>) -> String {
        let trimmed = candidate.trimmingCharacters(in: CharacterSet(charactersIn: ".:;,!? "))
        guard let title = plainText(trimmed, limit: RecipeLimits.maxTitleCharacters) else { return "" }
        guard title.split(separator: " ").count <= RecipeLimits.maxTitleWords else { return "" }
        let scan = RecipeScan(title)
        guard scan.allKeys.isSubset(of: instruction.allKeys) else { return "" }
        guard Set(scan.words).isSubset(of: allowed.union(RecipeWords.neutralVerbs)) else { return "" }
        return title
    }

    /// The model's timer stands when the instruction states that time. Otherwise the timer is
    /// the one time the instruction states, or none.
    static func timer(_ candidate: Int, instruction: RecipeScan) -> Int? {
        let stated = instruction.durations.flatMap(\.alternatives)
        if RecipeScan.isTimer(candidate), stated.contains(candidate) {
            return candidate
        }
        return instruction.singleTimer
    }

    // MARK: Location

    /// Copies the recipe out of a page from the lines the model pointed at. The draft's own
    /// name, yield, ingredients, and steps win over the page's wherever the draft has them.
    /// Returns nil when the lines do not make a recipe.
    static func located(_ location: RecipeModelLocation, in page: RecipePage, filling draft: RecipeDraft) -> RecipeDraft? {
        let ingredientLines = lines(location.firstIngredientLine, location.lastIngredientLine, in: page)
        let stepLines = lines(location.firstStepLine, location.lastStepLine, in: page)
        var recipe = draft
        if recipe.ingredients.isEmpty {
            // An ingredient list that runs into the steps is not a list.
            guard let ingredientLines, !(stepLines?.overlaps(ingredientLines) ?? false) else { return nil }
            recipe.ingredients = page.lines[ingredientLines].filter { !RecipePage.isSectionHeading($0) }
            let measured = recipe.ingredients.filter { !RecipeScan($0).quantities.isEmpty }.count
            guard measured * 2 >= recipe.ingredients.count else { return nil }
        }
        if recipe.steps.isEmpty {
            guard let stepLines else { return nil }
            recipe.steps = page.lines[stepLines].filter { !RecipePage.isSectionHeading($0) }
        }
        let taken = [ingredientLines, stepLines].compactMap { $0 }
        if recipe.name.isEmpty, let line = line(location.nameLine, in: page, outside: taken) {
            recipe.name = line
        }
        if recipe.yield.isEmpty, let line = line(location.yieldLine, in: page, outside: taken) {
            recipe.yield = line
        }
        recipe = recipe.cleaned()
        return recipe.hasRecipe ? recipe : nil
    }

    /// Positions in `page.lines` for a first and last line number, when they name a range.
    private static func lines(_ first: Int, _ last: Int, in page: RecipePage) -> Range<Int>? {
        guard first >= 1, first <= last, last <= page.lines.count else { return nil }
        return (first - 1)..<last
    }

    private static func line(_ number: Int, in page: RecipePage, outside taken: [Range<Int>]) -> String? {
        guard page.lines.indices.contains(number - 1), !taken.contains(where: { $0.contains(number - 1) }) else { return nil }
        return page.lines[number - 1]
    }
}

/// Which ingredient lines a step uses, worked out from the words: a step uses a line when it
/// says the line's main name. It is a reading aid. It misses an ingredient the step calls by
/// another word, and it may list a line that shares its main name with the one the step means.
struct RecipeIngredientIndex: Sendable {
    private struct Entry: Sendable {
        let line: String
        /// Every word of the line.
        let words: Set<String>
        /// The last naming word before the first comma or parenthesis: the "butter" of
        /// "unsalted butter, softened". Empty when the line names nothing.
        let head: String
    }

    private let entries: [Entry]
    /// Every word that names an ingredient of the recipe.
    let vocabulary: Set<String>

    /// - Parameters:
    ///   - lines: The ingredient lines as they will be shown.
    ///   - sources: The page's own lines, in the same order. Their words decide the matches.
    init(lines: [String], sources: [String]) {
        var vocabulary: Set<String> = []
        entries = zip(lines, sources).map { line, source in
            let names = Self.names(in: source)
            let lead = Self.names(in: String(source.prefix(while: { $0 != "," && $0 != "(" })))
            vocabulary.formUnion(names)
            return Entry(line: line, words: Set(RecipeScan(source).words), head: lead.last ?? names.last ?? "")
        }
        self.vocabulary = vocabulary
    }

    private static func names(in text: String) -> [String] {
        RecipeScan(text).words.filter { !RecipeWords.descriptors.contains($0) }
    }

    /// The lines an instruction names, in the list's order.
    func lines(usedBy instruction: String) -> [String] {
        let words = Set(RecipeScan(instruction).words)
        let matched = entries.filter { words.contains($0.head) }
        // Of two ingredients with one main name, such as two oils, the step means the one
        // whose other words it also uses.
        let exact = matched.filter { entry in
            let rivals = matched.filter { $0.head == entry.head && !$0.words.subtracting([$0.head]).isDisjoint(with: words) }
            return rivals.isEmpty || !entry.words.subtracting([entry.head]).isDisjoint(with: words)
        }
        return Array(exact.map(\.line).prefix(RecipeLimits.maxStepIngredients))
    }
}
