import Foundation

/// A recipe as a page gave it. Any part may be empty: a parser may have found all of it, some
/// of it, or nothing.
public struct RecipeDraft: Equatable, Sendable {
    public var name: String
    public var summary: String
    /// How much the recipe makes, as the page words it.
    public var yield: String
    /// Seconds.
    public var totalTime: TimeInterval?
    public var ingredients: [String]
    public var steps: [String]

    public init(
        name: String = "",
        summary: String = "",
        yield: String = "",
        totalTime: TimeInterval? = nil,
        ingredients: [String] = [],
        steps: [String] = []
    ) {
        self.name = name
        self.summary = summary
        self.yield = yield
        self.totalTime = totalTime
        self.ingredients = ingredients
        self.steps = steps
    }

    /// Whether there is enough to cook from.
    public var hasRecipe: Bool {
        !ingredients.isEmpty && !steps.isEmpty
    }

    /// The same recipe with every text on one line, list bullets and step labels removed, and
    /// empty entries dropped. No word, amount, or step is changed.
    public func cleaned() -> RecipeDraft {
        RecipeDraft(
            name: AssistantText.singleLine(name, limit: RecipeLimits.maxNameCharacters),
            summary: AssistantText.singleLine(summary, limit: RecipeLimits.maxSourceSummaryCharacters),
            yield: AssistantText.singleLine(yield, limit: RecipeLimits.maxYieldCharacters),
            totalTime: totalTime.flatMap { $0 > 0 ? $0 : nil },
            ingredients: ingredients.map(RecipeText.withoutBullet).filter { !$0.isEmpty },
            steps: steps.map { RecipeText.splitLabel(AssistantText.singleLine($0, limit: .max)).text }.filter { !$0.isEmpty }
        )
    }
}

/// A recipe laid out for the reader: tidy ingredient lines and short steps. Every amount,
/// temperature, time, and ingredient in it was checked against the page's own recipe.
public struct FormattedRecipe: Equatable, Sendable {
    public struct Step: Equatable, Sendable, Identifiable {
        /// Position in this recipe, starting at one.
        public let id: Int
        /// The step of the page's recipe this one came from, starting at one.
        public let sourceStepNumber: Int
        /// A few words that name the step, six at most. Empty when there is none.
        public let title: String
        public let instruction: String
        /// The ingredient lines this step names, as `FormattedRecipe.ingredients` words them.
        public let ingredients: [String]
        /// A time the step states, to offer as a timer.
        public let timerSeconds: Int?
        /// True when the instruction is the page's own text, because the model's version of
        /// this step did not pass the checks or was never written.
        public let isPageText: Bool
    }

    public let name: String
    /// One or two sentences. Empty when the page gave nothing to summarize.
    public let summary: String
    public let yield: String
    public let totalTime: TimeInterval?
    /// One line for each ingredient line of the page's recipe, in the same order.
    public let ingredients: [String]
    public let steps: [Step]
}

/// Why a recipe was not tidied.
public enum RecipeFormattingFailure: Error, Equatable, Sendable {
    /// Tidy Up Recipes is off in Settings.
    case turnedOff
    /// The reader closed, or another recipe was opened.
    case canceled
    /// The parser found no recipe and none could be located in the page's text.
    case noRecipeFound
    /// The page's text is longer than the parts of it the model was shown, and no recipe was
    /// located in those parts.
    case pageTooLong
    /// More ingredients or steps than the reader's limits.
    case recipeTooLong
    /// The model answered, and too little of the answer matched the page.
    case rejected
    case model(AssistantFailure)
}

/// What came of tidying one recipe. `original` can always be shown. `formatted` is there only
/// when the model's version passed every check against `original`.
public struct RecipeFormattingOutcome: Equatable, Sendable {
    /// The model's layout of the recipe. Nil means show `original`. Steps in it whose
    /// `isPageText` is true kept the page's wording.
    public let formatted: FormattedRecipe?
    /// The page's own recipe: the draft that was given, cleaned, with ingredients and steps
    /// copied line for line from the page's text when the draft had none.
    public let original: RecipeDraft
    /// True when the draft had no recipe and the model pointed out which lines of the page
    /// are the ingredients and the steps. The lines themselves are the page's.
    public let originalWasLocatedByModel: Bool
    /// Why there is no `formatted`. Nil exactly when there is one.
    public let failure: RecipeFormattingFailure?

    public var wasTidiedByModel: Bool {
        formatted != nil
    }

    static func tidied(_ formatted: FormattedRecipe, original: RecipeDraft, located: Bool) -> RecipeFormattingOutcome {
        RecipeFormattingOutcome(formatted: formatted, original: original, originalWasLocatedByModel: located, failure: nil)
    }

    static func plain(_ original: RecipeDraft, located: Bool = false, reason: RecipeFormattingFailure) -> RecipeFormattingOutcome {
        RecipeFormattingOutcome(formatted: nil, original: original, originalWasLocatedByModel: located, failure: reason)
    }
}

/// Something that can tidy a recipe. The app holds one and wraps it for the reader.
@MainActor
public protocol RecipeFormatting: AnyObject {
    /// Tidies one recipe. A second call cancels the first, and so does canceling the task that
    /// called. Never throws: when anything goes wrong the plain recipe comes back.
    /// - Parameters:
    ///   - draft: What the page's structured data gave. Any part may be empty.
    ///   - pageText: The page's readable text, one block to a line. Used only when the draft
    ///     has no ingredients or no steps.
    func format(draft: RecipeDraft, pageText: String) async -> RecipeFormattingOutcome
}

/// Numbers that bound what a recipe may hold and how long tidying may take.
public enum RecipeLimits {
    public static let maxNameCharacters = 100
    public static let maxSummaryCharacters = 220
    public static let maxSourceSummaryCharacters = 600
    public static let maxYieldCharacters = 60
    public static let maxIngredients = 60
    public static let maxIngredientCharacters = 200
    public static let maxSourceSteps = 40
    /// A longer step is never sent to the model and keeps the page's text.
    public static let maxSourceStepCharacters = 1_500
    /// The most short steps one step of the page may be split into.
    public static let maxPartsPerStep = 6
    public static let maxTitleCharacters = 48
    public static let maxTitleWords = 6
    public static let maxInstructionCharacters = 320
    public static let maxInstructionSentences = 3
    public static let maxStepIngredients = 8
    public static let maxTimerSeconds = 86_400
    /// Seconds one request to the model may take.
    public static let callTimeout: TimeInterval = 60
    /// Seconds after which no further request is started for a recipe.
    public static let totalTimeout: TimeInterval = 180
    /// The most steps, and the most ingredient lines, one request carries. Short requests keep
    /// a small model close to the text.
    public static let maxStepsPerRequest = 6
    public static let maxIngredientsPerRequest = 30
    /// Parts of a long page that are searched for a recipe, each in its own request.
    public static let maxPageWindows = 4
    /// The context size to plan for when the system reports none.
    public static let fallbackContextTokens = 4_096

    /// The context size to plan requests for, given what the system reports.
    public static func contextTokens(reported: Int) -> Int {
        reported > 0 ? reported : fallbackContextTokens
    }

    /// The share of a source sentence's words that the short steps must keep.
    static let sentenceRecall = 0.8
    /// The share of a summary's words that must come from the recipe.
    static let summaryPrecision = 0.75
}
