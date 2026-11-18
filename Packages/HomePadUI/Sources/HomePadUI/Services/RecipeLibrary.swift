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

/// The recipe reader's state: the page being loaded and the recipe on screen.
@MainActor
@Observable
public final class RecipeLibrary {
    public enum State: Equatable {
        case empty
        case loading
        case loaded(Recipe)
        case failed(RecipeLoadError)
    }

    public private(set) var state: State = .empty
    /// Ingredient lines the cook has checked off, for the recipe on screen.
    public private(set) var checkedIngredients: Set<Int> = []

    @ObservationIgnored private let loader: any RecipePageLoading

    public init(loader: any RecipePageLoading = URLSessionRecipePageLoader()) {
        self.loader = loader
    }

    public func load(address: String) async {
        guard let url = RecipeSourcePolicy.normalizedURL(from: address) else {
            state = .failed(.invalidAddress)
            return
        }
        await load(url: url)
    }

    public func load(url: URL) async {
        state = .loading
        checkedIngredients = []
        do throws(RecipeLoadError) {
            let html = try await loader.html(from: url)
            state = .loaded(try Self.parse(html))
        } catch {
            state = .failed(error)
        }
    }

    public func toggleIngredient(_ index: Int) {
        if !checkedIngredients.insert(index).inserted {
            checkedIngredients.remove(index)
        }
    }

    public func close() {
        state = .empty
        checkedIngredients = []
    }

    private static func parse(_ html: String) throws(RecipeLoadError) -> Recipe {
        do throws(RecipeParseError) {
            return try RecipeParser.parse(html: html)
        } catch {
            throw .parse(error)
        }
    }
}
