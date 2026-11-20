import Foundation
import FoundationModels
import HomePadAssistantCore
import HomePadCore

/// Where the recipe is in a numbered page. The model answers with line numbers only, so the
/// recipe's text is copied from the page and never written by the model.
@Generable
struct GeneratedRecipeLocation {
    @Guide(description: "The number of the line that names the dish. 0 when there is none.")
    var nameLine: Int
    @Guide(description: "The number of the line that says how much the recipe makes. 0 when there is none.")
    var yieldLine: Int
    @Guide(description: "The number of the first line of the ingredient list. 0 when there is none.")
    var firstIngredientLine: Int
    @Guide(description: "The number of the last line of the ingredient list. 0 when there is none.")
    var lastIngredientLine: Int
    @Guide(description: "The number of the first line of the cooking steps. 0 when there is none.")
    var firstStepLine: Int
    @Guide(description: "The number of the last line of the cooking steps. 0 when there is none.")
    var lastStepLine: Int
}

@Generable
struct GeneratedIngredientLine {
    @Guide(description: "The number of the ingredient line this rewrites.")
    var number: Int
    @Guide(description: "The same line with the amount first. Every word and amount is kept.")
    var text: String
}

@Generable
struct GeneratedRecipeOverview {
    @Guide(description: "One or two short sentences about the dish, using only what the text says.")
    var summary: String
    @Guide(description: "One entry for each numbered ingredient line, in the same order.", .maximumCount(RecipeLimits.maxIngredientsPerRequest))
    var ingredients: [GeneratedIngredientLine]
}

@Generable
struct GeneratedRecipeStep {
    @Guide(description: "The number of the step this short step came from.")
    var sourceStep: Int
    @Guide(description: "Two to five words that name the action, such as Brown the butter.")
    var title: String
    @Guide(description: "One action in one or two short sentences, in the page's own words, with every amount, temperature, and time kept.")
    var instruction: String
    @Guide(description: "How long the step says something takes, in seconds. 0 when it states no time.", .range(0...RecipeLimits.maxTimerSeconds))
    var timerSeconds: Int
}

@Generable
struct GeneratedRecipeSteps {
    @Guide(description: "The short steps, in the order of the steps they came from.", .maximumCount(RecipeLimits.maxStepsPerRequest * RecipeLimits.maxPartsPerStep))
    var steps: [GeneratedRecipeStep]
}

/// The language model on this device, as the recipe formatter uses it. Every request gets a
/// session of its own, so nothing a page said stays in a transcript and the whole context is
/// free for the request. No session is given a tool: the text of a web page can ask for
/// nothing but more text. Sampling is greedy, which the framework documents as always giving
/// the same output for the same input.
@MainActor
final class FoundationRecipeModel: RecipeModel {
    private let model: SystemLanguageModel

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    var contextTokens: Int {
        model.contextSize
    }

    func locate(_ request: RecipeModelRequest) async throws -> RecipeModelLocation {
        let location = try await respond(to: request, generating: GeneratedRecipeLocation.self)
        return RecipeModelLocation(
            nameLine: location.nameLine,
            yieldLine: location.yieldLine,
            firstIngredientLine: location.firstIngredientLine,
            lastIngredientLine: location.lastIngredientLine,
            firstStepLine: location.firstStepLine,
            lastStepLine: location.lastStepLine
        )
    }

    func overview(_ request: RecipeModelRequest) async throws -> RecipeModelOverview {
        let overview = try await respond(to: request, generating: GeneratedRecipeOverview.self)
        return RecipeModelOverview(
            summary: overview.summary,
            ingredients: overview.ingredients.map { RecipeModelLine(number: $0.number, text: $0.text) }
        )
    }

    func steps(_ request: RecipeModelRequest) async throws -> [RecipeModelStep] {
        try await respond(to: request, generating: GeneratedRecipeSteps.self).steps.map {
            RecipeModelStep(sourceStep: $0.sourceStep, title: $0.title, instruction: $0.instruction, timerSeconds: $0.timerSeconds)
        }
    }

    /// Throws `AssistantFailure`, or `CancellationError` when the task was canceled.
    private func respond<Content: Generable>(to request: RecipeModelRequest, generating type: Content.Type) async throws -> Content {
        guard model.isAvailable else { throw AssistantFailure.modelUnavailable }
        let instructions = Instructions(request.instructions)
        if await !fits(request, instructions: instructions, schema: type.generationSchema) {
            throw AssistantFailure.contextTooLong
        }
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(
                to: request.prompt,
                generating: type,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: request.maximumResponseTokens),
                contextOptions: ContextOptions(includeSchemaInPrompt: true)
            )
            try Task.checkCancellation()
            return response.content
        } catch let error as CancellationError {
            throw error
        } catch {
            throw AssistantFailure(FoundationModelResponder.kind(of: error))
        }
    }

    /// Counts the request with the model's own tokenizer. A request the count shows to be too
    /// long is not sent, so the caller can cut it in two. When the model cannot count, the
    /// request is sent and the session reports a context that is too small.
    private func fits(_ request: RecipeModelRequest, instructions: Instructions, schema: GenerationSchema) async -> Bool {
        do {
            let used = try await model.tokenCount(for: instructions)
                + model.tokenCount(for: schema)
                + model.tokenCount(for: request.prompt)
            return used + request.maximumResponseTokens <= RecipeLimits.contextTokens(reported: model.contextSize)
        } catch {
            return true
        }
    }
}

/// Tidies recipes with the language model on this device. One recipe at a time: a new call
/// cancels the one before it, and canceling the task that called cancels the request.
@MainActor
public final class FoundationModelRecipeFormatter: RecipeFormatting {
    private let formatter: RecipeFormatter

    /// - Parameter isEnabled: Read at each call. When false, the plain recipe comes back and
    ///   the model is not asked.
    public init(isEnabled: @escaping @MainActor () -> Bool = { true }) {
        formatter = RecipeFormatter(model: FoundationRecipeModel(), isEnabled: isEnabled)
    }

    public func format(draft: RecipeDraft, pageText: String) async -> RecipeFormattingOutcome {
        await formatter.format(draft: draft, pageText: pageText)
    }
}

public enum RecipeFormatters {
    /// The formatter the app uses: the language model on this device, or the script when the
    /// UI tests ask for it. Either one returns the plain recipe while Tidy Up Recipes is off
    /// in Settings, which is read again at every call.
    @MainActor
    public static func make(settings: HomePadSettings, hooks: AssistantTestHooks = .current) -> any RecipeFormatting {
        let isEnabled: @MainActor () -> Bool = { AssistantPreferences(settings: settings).formatsRecipes }
        if hooks.usesScriptedAssistant {
            return ScriptedRecipeFormatter(isEnabled: isEnabled, delay: .zero)
        }
        return FoundationModelRecipeFormatter(isEnabled: isEnabled)
    }
}
