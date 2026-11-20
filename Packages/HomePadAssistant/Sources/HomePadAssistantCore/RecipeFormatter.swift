import Foundation

/// The language model as the recipe formatter uses it: three kinds of request, each answered
/// once and independently of the others. An implementation keeps nothing between requests and
/// offers the model no tools, so a page can reach nothing but the text of its own recipe.
@MainActor
public protocol RecipeModel: AnyObject {
    /// How many tokens one request's instructions, prompt, and answer may take together, as
    /// the system reports it. Zero or less when the system does not say.
    var contextTokens: Int { get }
    /// Finds the recipe in a numbered page. Throws `AssistantFailure` or `CancellationError`.
    func locate(_ request: RecipeModelRequest) async throws -> RecipeModelLocation
    /// Rewrites ingredient lines and writes a summary. Throws as `locate` does.
    func overview(_ request: RecipeModelRequest) async throws -> RecipeModelOverview
    /// Splits steps into short steps. Throws as `locate` does.
    func steps(_ request: RecipeModelRequest) async throws -> [RecipeModelStep]
}

/// Tidies a recipe with a model and checks everything the model wrote against the page before
/// any of it is returned. The model is asked in parts that each fit its context: where the
/// recipe is, when the draft does not have one; the ingredient lines and a summary; then the
/// steps, a few at a time.
@MainActor
public final class RecipeFormatter: RecipeFormatting {
    private let model: any RecipeModel
    private let isEnabled: @MainActor () -> Bool
    private let now: @MainActor () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    /// Names the latest call. An earlier call that finds a newer number was replaced.
    private var run = 0
    /// Ends the request that is with the model right now.
    private var cancelRequest: (@MainActor () -> Void)?

    public init(
        model: any RecipeModel,
        isEnabled: @escaping @MainActor () -> Bool = { true },
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.model = model
        self.isEnabled = isEnabled
        self.now = now
        self.sleep = sleep
    }

    public func format(draft: RecipeDraft, pageText: String) async -> RecipeFormattingOutcome {
        run += 1
        cancelRequest?()
        cancelRequest = nil
        var job = Job(run: run, started: now(), recipe: draft.cleaned())
        guard isEnabled() else { return .plain(job.recipe, reason: .turnedOff) }
        let budget = RecipeBudget(contextTokens: RecipeLimits.contextTokens(reported: model.contextTokens))
        if !job.recipe.hasRecipe {
            if let failure = await locate(in: pageText, budget: budget, job: &job) {
                return .plain(job.recipe, reason: failure)
            }
        }
        guard job.recipe.ingredients.count <= RecipeLimits.maxIngredients,
              job.recipe.steps.count <= RecipeLimits.maxSourceSteps else {
            return .plain(job.recipe, located: job.located, reason: .recipeTooLong)
        }
        await tidyIngredients(budget: budget, job: &job)
        await tidySteps(budget: budget, job: &job)
        if job.failure == .canceled {
            return .plain(job.recipe, located: job.located, reason: .canceled)
        }
        // A recipe with most of its steps in the page's own words was not tidied.
        guard job.parts.count * 2 >= job.recipe.steps.count else {
            return .plain(job.recipe, located: job.located, reason: job.failure ?? .rejected)
        }
        return .tidied(assemble(job), original: job.recipe, located: job.located)
    }

    /// What one call has gathered so far.
    private struct Job {
        let run: Int
        let started: Date
        /// The page's recipe.
        var recipe: RecipeDraft
        var located = false
        var summary: String?
        /// Checked rewrites by ingredient line number.
        var ingredients: [Int: String] = [:]
        /// Checked short steps by step number.
        var parts: [Int: [RecipeCheckedPart]] = [:]
        /// The reason no further request is made.
        var failure: RecipeFormattingFailure?
    }

    // MARK: Requests

    /// Sends one request. Returns its answer, or why there is none: the call was replaced or
    /// its task canceled, the model failed, or the time ran out.
    private func ask<Answer: Sendable>(
        _ job: Job,
        _ request: @escaping @MainActor (any RecipeModel) async throws -> Answer
    ) async -> Result<Answer, RecipeFormattingFailure> {
        guard job.run == run, !Task.isCancelled else { return .failure(.canceled) }
        guard now().timeIntervalSince(job.started) < RecipeLimits.totalTimeout else { return .failure(.model(.timedOut)) }
        let (answers, continuation) = AsyncStream<Result<Answer, RecipeFormattingFailure>>.makeStream()
        let model = self.model
        let sleep = self.sleep
        let work = Task {
            do {
                continuation.yield(.success(try await request(model)))
            } catch is CancellationError {
                continuation.yield(.failure(.canceled))
            } catch {
                continuation.yield(.failure(.model(AssistantFailure(error))))
            }
        }
        let watchdog = Task {
            await sleep(RecipeLimits.callTimeout)
            continuation.yield(.failure(.model(.timedOut)))
        }
        cancelRequest = {
            continuation.yield(.failure(.canceled))
            work.cancel()
        }
        defer {
            work.cancel()
            watchdog.cancel()
        }
        // The stream ends without an answer when the task that called is canceled.
        var answer: Result<Answer, RecipeFormattingFailure> = .failure(.canceled)
        for await first in answers {
            answer = first
            break
        }
        guard job.run == run else { return .failure(.canceled) }
        cancelRequest = nil
        return answer
    }

    // MARK: Finding the recipe

    /// Fills the draft's missing ingredients and steps from the page. Returns why it could not.
    private func locate(in pageText: String, budget: RecipeBudget, job: inout Job) async -> RecipeFormattingFailure? {
        let windows = RecipePage.windows(pageText, characterBudget: budget.pageCharacters)
        for page in windows {
            let request = RecipePrompt.locate(page)
            switch await ask(job, { try await $0.locate(request) }) {
            case .success(let location):
                if let recipe = RecipeValidator.located(location, in: page, filling: job.recipe) {
                    job.recipe = recipe
                    job.located = true
                    return nil
                }
            case .failure(let failure):
                return failure
            }
        }
        return windows.last?.wasCut == true ? .pageTooLong : .noRecipeFound
    }

    // MARK: Ingredients and steps

    private func tidyIngredients(budget: RecipeBudget, job: inout Job) async {
        let header = RecipePrompt.ingredientHeaderCharacters(job.recipe)
        var chunks = RecipeChunks.pack(
            job.recipe.ingredients.map(\.count),
            budget: budget.ingredientCharacters(header: header),
            maxItems: RecipeLimits.maxIngredientsPerRequest
        )
        var isFirst = true
        while job.failure == nil, !chunks.isEmpty {
            let chunk = chunks.removeFirst()
            let request = RecipePrompt.ingredients(job.recipe, indices: chunk)
            switch await ask(job, { try await $0.overview(request) }) {
            case .success(let overview):
                for (number, line) in RecipeValidator.ingredientLines(overview.ingredients, request: request) {
                    job.ingredients[number] = line
                }
                if isFirst {
                    job.summary = RecipeValidator.summary(overview.summary, recipe: job.recipe)
                }
            case .failure(let failure):
                chunks.insert(contentsOf: recover(from: failure, chunk: chunk, job: &job), at: 0)
            }
            isFirst = false
        }
    }

    private func tidySteps(budget: RecipeBudget, job: inout Job) async {
        let vocabulary = RecipeIngredientIndex(lines: job.recipe.ingredients, sources: job.recipe.ingredients).vocabulary
        var chunks = RecipeChunks.pack(
            job.recipe.steps.map(\.count),
            budget: budget.stepCharacters,
            maxItems: RecipeLimits.maxStepsPerRequest,
            itemLimit: RecipeLimits.maxSourceStepCharacters
        )
        while job.failure == nil, !chunks.isEmpty {
            let chunk = chunks.removeFirst()
            let request = RecipePrompt.steps(job.recipe, indices: chunk)
            switch await ask(job, { try await $0.steps(request) }) {
            case .success(let steps):
                for (number, parts) in RecipeValidator.steps(steps, request: request, vocabulary: vocabulary) {
                    job.parts[number] = parts
                }
            case .failure(let failure):
                chunks.insert(contentsOf: recover(from: failure, chunk: chunk, job: &job), at: 0)
            }
        }
    }

    /// Decides what follows a failed request. A request that was too long for the model is
    /// asked again in two halves. One the model declined is skipped, and its lines keep the
    /// page's text. Anything else ends the requests for this recipe.
    private func recover(from failure: RecipeFormattingFailure, chunk: [Int], job: inout Job) -> [[Int]] {
        switch failure {
        case .model(.contextTooLong):
            guard chunk.count > 1 else { return [] }
            let middle = chunk.count / 2
            return [Array(chunk[..<middle]), Array(chunk[middle...])]
        case .model(.refused):
            return []
        default:
            job.failure = failure
            return []
        }
    }

    // MARK: Result

    private func assemble(_ job: Job) -> FormattedRecipe {
        let recipe = job.recipe
        let ingredients = recipe.ingredients.enumerated().map { job.ingredients[$0.offset + 1] ?? $0.element }
        let index = RecipeIngredientIndex(lines: ingredients, sources: recipe.ingredients)
        var steps: [FormattedRecipe.Step] = []
        for (offset, source) in recipe.steps.enumerated() {
            let parts = job.parts[offset + 1] ?? [RecipeCheckedPart(title: "", instruction: source, timerSeconds: RecipeScan(source).singleTimer)]
            for part in parts {
                steps.append(FormattedRecipe.Step(
                    id: steps.count + 1,
                    sourceStepNumber: offset + 1,
                    title: part.title,
                    instruction: part.instruction,
                    ingredients: index.lines(usedBy: part.instruction),
                    timerSeconds: part.timerSeconds,
                    isPageText: job.parts[offset + 1] == nil
                ))
            }
        }
        return FormattedRecipe(
            name: recipe.name,
            summary: job.summary ?? RecipeText.shortSummary(recipe.summary),
            yield: recipe.yield,
            totalTime: recipe.totalTime,
            ingredients: ingredients,
            steps: steps
        )
    }
}
