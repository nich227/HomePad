import Foundation
import HomePadUICore
import Observation

public enum RecipeLoadError: Error, Equatable, Sendable {
    case invalidAddress
    case network
    case parse(RecipeParseError)
}

/// Fetches the raw page for a recipe. Behind a protocol so previews and tests need no network.
public protocol RecipePageLoading: Sendable {
    func html(from url: URL) async throws(RecipeLoadError) -> String
}

/// Fetches with a throwaway session: no cookies, no cache, no credentials.
public struct URLSessionRecipePageLoader: RecipePageLoading {
    public init() {}

    public func html(from url: URL) async throws(RecipeLoadError) -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw .network }
        guard data.count <= RecipeParser.maximumBytes else { throw .parse(.pageTooLarge) }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Returns canned pages, for previews.
public struct FixedRecipePageLoader: RecipePageLoading {
    private let html: String?

    public init(html: String?) {
        self.html = html
    }

    public func html(from url: URL) async throws(RecipeLoadError) -> String {
        guard let html else { throw .network }
        return html
    }
}

/// A stand-in enhancer for previews and UI tests. It needs no model: it splits each step into
/// one action per step, names it with its first few words, and lists the ingredients whose
/// main word the step mentions. It answers after a short pause, so the swap can be seen.
public struct SampleRecipeEnhancer: RecipeEnhancing {
    private let delay: Duration

    public init(delay: Duration = .seconds(1.5)) {
        self.delay = delay
    }

    @MainActor
    public func enhance(recipe: Recipe?, pageText: String, title: String) async -> Recipe? {
        try? await Task.sleep(for: delay)
        guard let recipe, !Task.isCancelled else { return nil }
        var steps: [RecipeStep] = []
        for step in recipe.steps {
            let actions = step.text
                .split(separator: ". ")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
                .filter { !$0.isEmpty }
            for action in actions {
                let words = action.split(separator: " ")
                let lowered = action.lowercased()
                let used = recipe.ingredients.filter { line in
                    line.lowercased()
                        .split { !$0.isLetter }
                        .contains { $0.count > 3 && !Self.fillers.contains(String($0)) && lowered.contains($0) }
                }
                steps.append(RecipeStep(
                    id: steps.count + 1,
                    title: words.prefix(3).joined(separator: " "),
                    text: action + ".",
                    timer: RecipeTimers.duration(in: action),
                    ingredients: used,
                    sourceStepID: step.id
                ))
            }
        }
        return Recipe(name: recipe.name, ingredients: recipe.ingredients, sections: [RecipeSection(steps: steps)], isTidied: true)
    }

    private static let fillers: Set<String> = ["cups", "tablespoons", "teaspoons", "cloves", "fresh", "chopped", "peeled", "cubed", "leaves", "large", "small", "yellow"]
}

/// The recipe reader's state: the page being loaded, the recipe on screen, and the cook's place
/// in it. With an enhancer, the page's own recipe shows at once and the tidied one takes its
/// place when it arrives.
@MainActor
@Observable
public final class RecipeLibrary {
    public enum State: Equatable {
        case empty
        case loading
        /// The page has no recipe of its own and the enhancer is reading its text.
        case preparing
        case loaded(Recipe)
        case failed(RecipeLoadError)
    }

    /// The visit to the reader: both versions of the recipe, which one shows, and the place.
    public private(set) var session = RecipeSession()
    private var failure: RecipeLoadError?

    @ObservationIgnored private let loader: any RecipePageLoading
    @ObservationIgnored private let enhancer: (any RecipeEnhancing)?
    @ObservationIgnored private var enhancement: Task<Void, Never>?

    /// - Parameter enhancer: Rewrites a recipe for the reader. Nil shows recipes as their pages
    ///   give them.
    public init(loader: any RecipePageLoading = URLSessionRecipePageLoader(), enhancer: (any RecipeEnhancing)? = nil) {
        self.loader = loader
        self.enhancer = enhancer
    }

    public var state: State {
        if let failure { return .failed(failure) }
        switch session.phase {
        case .empty: return .empty
        case .loading: return .loading
        case .preparing: return .preparing
        case .notFound: return .failed(.parse(.noRecipe))
        case .reading: return session.recipe.map(State.loaded) ?? .empty
        }
    }

    /// Ingredient lines the cook has checked off, for the recipe on screen.
    public var checkedIngredients: Set<Int> { session.checkedIngredients }
    /// The step in front, counted from zero.
    public var stepIndex: Int { session.stepIndex }
    /// True while the recipe on screen is the tidied one.
    public var isShowingTidied: Bool { session.recipe?.isTidied ?? false }
    /// True when the cook can switch between the tidied recipe and the page's own words.
    public var canSwitchToOriginal: Bool { session.canSwitch }

    public func load(address: String) async {
        guard let url = RecipeSourcePolicy.normalizedURL(from: address) else {
            enhancement?.cancel()
            session.close()
            failure = .invalidAddress
            return
        }
        await load(url: url)
    }

    public func load(url: URL) async {
        enhancement?.cancel()
        failure = nil
        let token = session.begin()
        let html: String
        do throws(RecipeLoadError) {
            html = try await loader.html(from: url)
        } catch {
            fail(error, token: token)
            return
        }
        guard token == session.token else { return }
        let parsed: Recipe?
        var parseError = RecipeParseError.noRecipe
        do throws(RecipeParseError) {
            parsed = try RecipeParser.parse(html: html)
        } catch {
            parsed = nil
            parseError = error
        }
        // A page too large to read is not handed to anything.
        let enhancer = parseError == .pageTooLarge ? nil : enhancer
        let asks = session.pageRead(parsed, canEnhance: enhancer != nil, token: token)
        if parsed == nil, !asks {
            fail(.parse(parseError), token: token)
        }
        guard asks, let enhancer else { return }
        // The page's text lives only in this task. Nothing keeps it once the task ends.
        let pageText = HTMLText.readable(html, limit: RecipeEnhancement.maximumPageTextLength)
        let title = HTMLText.title(in: html)
        enhancement = Task { [weak self] in
            let result = await enhancer.enhance(recipe: parsed, pageText: pageText, title: title)
            guard !Task.isCancelled, let self else { return }
            self.session.enhanced(result, token: token)
            if self.session.phase == .notFound {
                self.fail(.parse(parseError), token: token)
            }
        }
    }

    public func toggleIngredient(_ index: Int) {
        session.toggleIngredient(index)
    }

    public func goToStep(_ index: Int) {
        session.goToStep(index)
    }

    /// Shows the page's own words, or the tidied recipe again. The cook's place is kept.
    public func setShowsOriginal(_ showsOriginal: Bool) {
        session.setShowsOriginal(showsOriginal)
    }

    /// Call when the reader goes off screen with a recipe still open. A request to the enhancer
    /// still under way is cancelled, and the recipe stays as the page gave it.
    public func leaveReader() {
        enhancement?.cancel()
        enhancement = nil
        session.abandonEnhancement()
    }

    /// Leaves the reader. A request to the enhancer still under way is cancelled.
    public func close() {
        enhancement?.cancel()
        enhancement = nil
        failure = nil
        session.close()
    }

    private func fail(_ error: RecipeLoadError, token: Int) {
        guard token == session.token else { return }
        session.close()
        failure = error
    }
}
