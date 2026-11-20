import Foundation

/// Something that can rewrite a recipe so it reads well from across a kitchen: short step
/// titles, one action per step, the ingredients each step uses. The app supplies one; the
/// reader works without it.
public protocol RecipeEnhancing: Sendable {
    /// - Parameters:
    ///   - recipe: What the page's structured data gave, or nil when it had none.
    ///   - pageText: The page's readable text, cut off at `RecipeEnhancement.maximumPageTextLength`.
    ///   - title: The page's title, or an empty string.
    /// - Returns: The rewritten recipe, or nil when there is nothing better to show.
    @MainActor func enhance(recipe: Recipe?, pageText: String, title: String) async -> Recipe?
}

public enum RecipeEnhancement {
    /// How much of a page's text is handed to an enhancer, in characters.
    public static let maximumPageTextLength = 12_000
    /// The most ingredient lines shown for one step.
    public static let maximumStepIngredients = 8

    /// What the reader takes from an enhancer: a recipe with a name and at least one step with
    /// text. Steps are numbered again from one, a step that points at a step the original does
    /// not have loses the pointer, a step without a timer gets one from a duration in its text,
    /// and whatever the enhancer left out is filled in from the original. Nil when the result is
    /// not usable.
    public static func accepted(_ enhanced: Recipe?, original: Recipe?) -> Recipe? {
        guard let enhanced else { return nil }
        let name = enhanced.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let originalIDs = Set(original?.steps.map(\.id) ?? [])
        var number = 0
        let sections = enhanced.sections.compactMap { section -> RecipeSection? in
            let steps = section.steps.compactMap { step -> RecipeStep? in
                let text = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                number += 1
                let title = step.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let lines = step.ingredients
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return RecipeStep(
                    id: number,
                    title: title.flatMap { $0.isEmpty ? nil : $0 },
                    text: text,
                    timer: step.timer ?? RecipeTimers.duration(in: text),
                    ingredients: Array(lines.prefix(maximumStepIngredients)),
                    sourceStepID: step.sourceStepID.flatMap { originalIDs.contains($0) ? $0 : nil }
                )
            }
            return steps.isEmpty ? nil : RecipeSection(name: section.name, steps: steps)
        }
        guard !sections.isEmpty else { return nil }
        return Recipe(
            name: name,
            summary: enhanced.summary ?? original?.summary,
            author: enhanced.author ?? original?.author,
            imageURL: enhanced.imageURL ?? original?.imageURL,
            yield: enhanced.yield ?? original?.yield,
            prepTime: enhanced.prepTime ?? original?.prepTime,
            cookTime: enhanced.cookTime ?? original?.cookTime,
            totalTime: enhanced.totalTime ?? original?.totalTime,
            ingredients: enhanced.ingredients.isEmpty ? original?.ingredients ?? [] : enhanced.ingredients,
            sections: sections,
            isTidied: true
        )
    }
}

/// Where the cook is in one version of a recipe, carried over to another version of it.
public enum RecipePlace {
    /// The step to show in `new` for someone on step `index` of `old`. A step that says which
    /// original step it came from is matched exactly; otherwise the same share of the way
    /// through.
    public static func step(_ index: Int, from old: Recipe?, to new: Recipe) -> Int {
        let newSteps = new.steps
        guard let oldSteps = old?.steps, oldSteps.indices.contains(index), !newSteps.isEmpty else { return 0 }
        let current = oldSteps[index]
        if let match = newSteps.firstIndex(where: { $0.sourceStepID == current.id }) {
            return match
        }
        if let source = current.sourceStepID, let match = newSteps.firstIndex(where: { $0.id == source }) {
            return match
        }
        if newSteps.count == oldSteps.count {
            return index
        }
        return min(newSteps.count - 1, index * newSteps.count / oldSteps.count)
    }

    /// The ingredient lines of `new` that stand for the checked lines of `old`: the same
    /// positions when the lists are the same length, and otherwise the lines with the same
    /// words. A line with no counterpart is no longer checked.
    public static func checked(_ checked: Set<Int>, from old: Recipe?, to new: Recipe) -> Set<Int> {
        guard let old else { return [] }
        let valid = checked.filter { old.ingredients.indices.contains($0) }
        if old.ingredients.count == new.ingredients.count {
            return valid
        }
        let positions = Dictionary(new.ingredients.enumerated().map { (normalized($0.element), $0.offset) }, uniquingKeysWith: { first, _ in first })
        return Set(valid.compactMap { positions[normalized(old.ingredients[$0])] })
    }

    static func normalized(_ line: String) -> String {
        line.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// One visit to the recipe reader: the page's own recipe, the tidied one when it arrives, which
/// of the two is showing, and the cook's place. The reader shows the page's recipe at once and
/// never waits for an enhancer.
public struct RecipeSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case empty
        /// The page is on its way.
        case loading
        /// The page had no recipe of its own and an enhancer is reading its text.
        case preparing
        /// A recipe is on screen.
        case reading
        /// Neither the page nor an enhancer gave a recipe.
        case notFound
    }

    public private(set) var phase = Phase.empty
    /// The recipe as the page gave it.
    public private(set) var original: Recipe?
    /// The recipe as an enhancer rewrote it.
    public private(set) var tidied: Recipe?
    /// True while the cook has asked for the page's own words.
    public private(set) var showsOriginal = false
    /// True while an enhancer has been asked and has not answered.
    public private(set) var isEnhancing = false
    /// The step in front, counted from zero in the recipe that is showing.
    public private(set) var stepIndex = 0
    /// Ingredient lines the cook has checked off, in the recipe that is showing.
    public private(set) var checkedIngredients: Set<Int> = []
    /// Names this visit. An answer that carries an older token is for a recipe that has gone.
    public private(set) var token = 0

    public init() {}

    /// The recipe to show: the tidied one when there is one, unless the cook asked for the
    /// original.
    public var recipe: Recipe? {
        showsOriginal ? original : tidied ?? original
    }

    /// Whether there are two versions to switch between.
    public var canSwitch: Bool {
        original != nil && tidied != nil
    }

    /// Starts a visit: everything from the one before is dropped. Returns the visit's token.
    @discardableResult
    public mutating func begin() -> Int {
        self = RecipeSession(token: token + 1, phase: .loading)
        return token
    }

    /// The page arrived. `recipe` is what its structured data gave, if anything. Returns whether
    /// to ask the enhancer.
    @discardableResult
    public mutating func pageRead(_ recipe: Recipe?, canEnhance: Bool, token: Int) -> Bool {
        guard token == self.token, phase == .loading else { return false }
        original = recipe
        isEnhancing = canEnhance
        phase = recipe != nil ? .reading : (canEnhance ? .preparing : .notFound)
        return canEnhance
    }

    /// The enhancer answered. A usable recipe takes the place of the one on screen and the
    /// cook's step and checked ingredients go with them. No recipe leaves things as they are,
    /// or, when there was nothing on screen, ends the visit as not found.
    public mutating func enhanced(_ result: Recipe?, token: Int) {
        guard token == self.token, isEnhancing else { return }
        isEnhancing = false
        guard let accepted = RecipeEnhancement.accepted(result, original: original) else {
            if original == nil {
                phase = .notFound
            }
            return
        }
        tidied = accepted
        phase = .reading
        carryPlace(from: original, to: accepted)
    }

    /// Switches between the page's own words and the tidied recipe, keeping the cook's place.
    public mutating func setShowsOriginal(_ value: Bool) {
        guard let original, let tidied, value != showsOriginal else { return }
        showsOriginal = value
        carryPlace(from: value ? tidied : original, to: value ? original : tidied)
    }

    public mutating func toggleIngredient(_ index: Int) {
        guard let recipe, recipe.ingredients.indices.contains(index) else { return }
        if !checkedIngredients.insert(index).inserted {
            checkedIngredients.remove(index)
        }
    }

    /// Goes to a step, kept within the recipe.
    public mutating func goToStep(_ index: Int) {
        let count = recipe?.steps.count ?? 0
        stepIndex = min(max(index, 0), max(count - 1, 0))
    }

    /// The cook left the reader while the enhancer was still working. Its answer is no longer
    /// wanted: a recipe on screen stays as the page gave it, and a visit that had nothing to
    /// show yet ends.
    public mutating func abandonEnhancement() {
        guard isEnhancing else { return }
        if original == nil {
            close()
        } else {
            isEnhancing = false
        }
    }

    /// Ends the visit. An answer still on its way is ignored when it comes.
    public mutating func close() {
        self = RecipeSession(token: token + 1, phase: .empty)
    }

    private init(token: Int, phase: Phase) {
        self.token = token
        self.phase = phase
    }

    private mutating func carryPlace(from old: Recipe?, to new: Recipe) {
        stepIndex = RecipePlace.step(stepIndex, from: old, to: new)
        checkedIngredients = RecipePlace.checked(checkedIngredients, from: old, to: new)
    }
}
