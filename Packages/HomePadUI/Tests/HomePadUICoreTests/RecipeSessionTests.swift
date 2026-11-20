import Foundation
import Testing
@testable import HomePadUICore

@Suite struct RecipeSessionTests {
    private let page = Recipe(
        name: "Soup",
        author: "Home Cookbook",
        imageURL: URL(string: "https://example.com/soup.jpg"),
        yield: "Serves 4",
        totalTime: 2100,
        ingredients: ["1 squash", "1 onion", "4 cups stock"],
        sections: [RecipeSection(steps: [
            RecipeStep(id: 1, text: "Cook the onion. Add the squash."),
            RecipeStep(id: 2, text: "Simmer for 20 minutes.", timer: 1200),
            RecipeStep(id: 3, text: "Blend."),
        ])]
    )

    /// Five steps from the page's three, each saying which step it came from.
    private let rewritten = Recipe(
        name: "Soup",
        ingredients: ["1 squash", "1 onion", "4 cups stock"],
        sections: [RecipeSection(steps: [
            RecipeStep(id: 10, title: "Soften the onion", text: "Cook the onion.", ingredients: ["1 onion"], sourceStepID: 1),
            RecipeStep(id: 11, title: "Add the squash", text: "Add the squash.", ingredients: ["1 squash"], sourceStepID: 1),
            RecipeStep(id: 12, title: "Simmer", text: "Simmer for 20 minutes.", ingredients: ["4 cups stock"], sourceStepID: 2),
            RecipeStep(id: 13, title: "Blend", text: "Blend until smooth.", sourceStepID: 3),
            RecipeStep(id: 14, title: "Serve", text: "Serve hot.", sourceStepID: 9),
        ])]
    )

    private func reading(canEnhance: Bool = true) -> (RecipeSession, Int) {
        var session = RecipeSession()
        let token = session.begin()
        session.pageRead(page, canEnhance: canEnhance, token: token)
        return (session, token)
    }

    @Test func pageRead_whenThePageHasARecipe_thenItShowsAtOnceWhileTheEnhancerWorks() {
        var session = RecipeSession()
        #expect(session.phase == .empty && session.recipe == nil)
        let token = session.begin()
        #expect(session.phase == .loading && token == 1)
        let asks = session.pageRead(page, canEnhance: true, token: token)
        #expect(asks)
        #expect(session.phase == .reading && session.recipe == page && session.isEnhancing)
        #expect(!session.canSwitch)
        let (plain, _) = reading(canEnhance: false)
        #expect(plain.phase == .reading && !plain.isEnhancing)
    }

    @Test func pageRead_whenThePageHasNoRecipe_thenPreparingWithAnEnhancerAndNotFoundWithout() {
        var session = RecipeSession()
        var token = session.begin()
        let asks = session.pageRead(nil, canEnhance: true, token: token)
        #expect(asks)
        #expect(session.phase == .preparing && session.recipe == nil && session.isEnhancing)
        token = session.begin()
        let asksWithout = session.pageRead(nil, canEnhance: false, token: token)
        #expect(!asksWithout)
        #expect(session.phase == .notFound)
        // A page that arrives twice, or for a visit that has ended, changes nothing.
        let again = session.pageRead(page, canEnhance: true, token: token)
        let stale = session.pageRead(page, canEnhance: true, token: token - 1)
        #expect(!again && !stale)
        #expect(session.phase == .notFound && session.original == nil)
    }

    @Test func enhanced_whenTheTidiedRecipeArrives_thenItSwapsInAndKeepsThePlaceAndTheChecks() {
        var (session, token) = reading()
        session.goToStep(1)
        session.toggleIngredient(2)
        session.toggleIngredient(0)
        session.enhanced(rewritten, token: token)
        #expect(session.phase == .reading && !session.isEnhancing && session.canSwitch)
        #expect(session.recipe?.isTidied == true && session.original == page)
        // Step 2 of the page became step 3 of the tidied recipe.
        #expect(session.stepIndex == 2)
        #expect(session.recipe?.steps[2].title == "Simmer")
        #expect(session.checkedIngredients == [0, 2])
        // A second answer for the same visit is not taken.
        session.enhanced(page, token: token)
        #expect(session.tidied?.steps.count == 5)
    }

    @Test func enhanced_whenThePageHadNoRecipe_thenTheEnhancersRecipeShowsOrTheVisitEndsNotFound() {
        var session = RecipeSession()
        var token = session.begin()
        session.pageRead(nil, canEnhance: true, token: token)
        session.enhanced(rewritten, token: token)
        #expect(session.phase == .reading && session.recipe?.isTidied == true)
        #expect(!session.canSwitch && session.stepIndex == 0)
        session.setShowsOriginal(true)
        #expect(!session.showsOriginal)
        token = session.begin()
        session.pageRead(nil, canEnhance: true, token: token)
        session.enhanced(nil, token: token)
        #expect(session.phase == .notFound && session.recipe == nil)
    }

    @Test func enhanced_whenTheAnswerIsNothingOrUnusable_thenThePagesRecipeStays() {
        var (session, token) = reading()
        session.goToStep(2)
        session.enhanced(Recipe(name: " ", sections: rewritten.sections), token: token)
        #expect(session.phase == .reading && session.recipe == page && session.tidied == nil)
        #expect(session.stepIndex == 2 && !session.isEnhancing)
    }

    @Test func enhanced_whenTheVisitHasEndedOrAnotherBegan_thenTheAnswerIsIgnored() {
        var (session, token) = reading()
        session.close()
        session.enhanced(rewritten, token: token)
        #expect(session.phase == .empty && session.recipe == nil && session.tidied == nil)
        let next = session.begin()
        #expect(next == token + 2)
        session.pageRead(page, canEnhance: true, token: next)
        session.enhanced(rewritten, token: token)
        #expect(session.tidied == nil && session.isEnhancing)
    }

    @Test func abandonEnhancement_whenTheCookLeaves_thenTheAnswerIsNoLongerWanted() {
        var (session, token) = reading()
        session.abandonEnhancement()
        #expect(!session.isEnhancing && session.recipe == page)
        session.enhanced(rewritten, token: token)
        #expect(session.tidied == nil)
        session.abandonEnhancement()
        #expect(session.phase == .reading)
        var waiting = RecipeSession()
        let other = waiting.begin()
        waiting.pageRead(nil, canEnhance: true, token: other)
        waiting.abandonEnhancement()
        #expect(waiting.phase == .empty && waiting.token == other + 1)
    }

    @Test func setShowsOriginal_whenSwitchedBackAndForth_thenThePlaceFollows() {
        var (session, token) = reading()
        session.enhanced(rewritten, token: token)
        session.goToStep(1)
        session.setShowsOriginal(true)
        #expect(session.showsOriginal && session.recipe == page)
        // "Add the squash" came from the page's first step.
        #expect(session.stepIndex == 0)
        session.setShowsOriginal(true)
        #expect(session.stepIndex == 0)
        session.goToStep(2)
        session.setShowsOriginal(false)
        #expect(!session.showsOriginal && session.recipe?.isTidied == true)
        #expect(session.stepIndex == 3)
    }

    @Test func stepsAndIngredients_whenOutOfRange_thenKeptWithinTheRecipe() {
        var (session, _) = reading()
        session.goToStep(99)
        #expect(session.stepIndex == 2)
        session.goToStep(-4)
        #expect(session.stepIndex == 0)
        session.toggleIngredient(7)
        session.toggleIngredient(-1)
        #expect(session.checkedIngredients.isEmpty)
        session.toggleIngredient(1)
        session.toggleIngredient(1)
        #expect(session.checkedIngredients.isEmpty)
        var empty = RecipeSession()
        empty.goToStep(3)
        empty.toggleIngredient(0)
        #expect(empty.stepIndex == 0 && empty.checkedIngredients.isEmpty)
    }
}

@Suite struct RecipeEnhancementTests {
    private let original = Recipe(
        name: "Soup",
        summary: "Warm",
        author: "Home Cookbook",
        imageURL: URL(string: "https://example.com/soup.jpg"),
        yield: "Serves 4",
        prepTime: 600,
        cookTime: 1500,
        totalTime: 2100,
        ingredients: ["1 squash"],
        sections: [RecipeSection(steps: [RecipeStep(id: 1, text: "Cook.")])]
    )

    @Test func accepted_whenUsable_thenRenumberedMarkedTidiedAndFilledInFromTheOriginal() throws {
        let enhanced = Recipe(name: " Squash Soup ", sections: [
            RecipeSection(name: "Base", steps: [
                RecipeStep(id: 7, title: " Soften ", text: " Cook for 5 minutes. ", ingredients: [" 1 onion ", "", "2 cloves garlic"], sourceStepID: 1),
                RecipeStep(id: 7, title: "  ", text: "   "),
            ]),
            RecipeSection(steps: [RecipeStep(id: 3, text: "")]),
            RecipeSection(steps: [RecipeStep(id: 9, text: "Blend.", timer: 30, ingredients: Array(repeating: "salt", count: 20), sourceStepID: 5)]),
        ])
        let recipe = try #require(RecipeEnhancement.accepted(enhanced, original: original))
        #expect(recipe.isTidied && recipe.name == "Squash Soup")
        #expect(recipe.sections.count == 2 && recipe.sections[0].name == "Base")
        #expect(recipe.steps.map(\.id) == [1, 2])
        #expect(recipe.steps[0] == RecipeStep(id: 1, title: "Soften", text: "Cook for 5 minutes.", timer: 300, ingredients: ["1 onion", "2 cloves garlic"], sourceStepID: 1))
        #expect(recipe.steps[1].timer == 30 && recipe.steps[1].sourceStepID == nil)
        #expect(recipe.steps[1].ingredients.count == RecipeEnhancement.maximumStepIngredients)
        #expect(recipe.summary == "Warm" && recipe.author == "Home Cookbook" && recipe.yield == "Serves 4")
        #expect(recipe.imageURL == original.imageURL && recipe.ingredients == ["1 squash"])
        #expect(recipe.prepTime == 600 && recipe.cookTime == 1500 && recipe.totalTime == 2100)
    }

    @Test func accepted_whenTheEnhancerGivesItsOwnDetails_thenThoseAreKept() throws {
        let enhanced = Recipe(name: "Soup", summary: "Cozy", author: "Me", yield: "2", prepTime: 1, cookTime: 2, totalTime: 3, ingredients: ["2 onions"], sections: [RecipeSection(steps: [RecipeStep(id: 1, title: nil, text: "Stir.")])])
        let recipe = try #require(RecipeEnhancement.accepted(enhanced, original: nil))
        #expect(recipe.summary == "Cozy" && recipe.author == "Me" && recipe.yield == "2" && recipe.ingredients == ["2 onions"])
        #expect(recipe.prepTime == 1 && recipe.cookTime == 2 && recipe.totalTime == 3 && recipe.imageURL == nil)
        #expect(recipe.steps[0].title == nil && recipe.steps[0].timer == nil)
        let bare = try #require(RecipeEnhancement.accepted(Recipe(name: "Soup", sections: enhanced.sections), original: nil))
        #expect(bare.ingredients.isEmpty && bare.summary == nil)
    }

    @Test func accepted_whenThereIsNoNameOrNoStepWithText_thenNil() {
        #expect(RecipeEnhancement.accepted(nil, original: original) == nil)
        #expect(RecipeEnhancement.accepted(Recipe(name: "", sections: original.sections), original: original) == nil)
        #expect(RecipeEnhancement.accepted(Recipe(name: "Soup", sections: []), original: original) == nil)
        #expect(RecipeEnhancement.accepted(Recipe(name: "Soup", sections: [RecipeSection(steps: [RecipeStep(id: 1, text: " ")])]), original: original) == nil)
    }

    @Test func place_whenStepsDoNotSayWhereTheyCameFrom_thenTheSameShareOfTheWayThrough() {
        func recipe(_ count: Int) -> Recipe {
            Recipe(name: "R", sections: [RecipeSection(steps: (1...max(count, 1)).prefix(count).map { RecipeStep(id: $0 + 100 * count, text: "s") })])
        }
        #expect(RecipePlace.step(1, from: recipe(3), to: recipe(3)) == 1)
        #expect(RecipePlace.step(1, from: recipe(2), to: recipe(6)) == 3)
        #expect(RecipePlace.step(5, from: recipe(6), to: recipe(2)) == 1)
        #expect(RecipePlace.step(0, from: recipe(4), to: recipe(9)) == 0)
        #expect(RecipePlace.step(2, from: nil, to: recipe(3)) == 0)
        #expect(RecipePlace.step(8, from: recipe(3), to: recipe(3)) == 0)
        #expect(RecipePlace.step(1, from: recipe(3), to: recipe(0)) == 0)
    }

    @Test func place_whenIngredientListsDiffer_thenChecksFollowTheSameWords() {
        let old = Recipe(name: "R", ingredients: ["1 Onion", "2  cups stock", "salt"], sections: [])
        let same = Recipe(name: "R", ingredients: ["an onion", "stock", "a pinch of salt"], sections: [])
        let longer = Recipe(name: "R", ingredients: ["butter", "2 cups stock", "1 onion", "1 onion"], sections: [])
        #expect(RecipePlace.checked([0, 2, 9], from: old, to: same) == [0, 2])
        #expect(RecipePlace.checked([0, 1, 2], from: old, to: longer) == [1, 2])
        #expect(RecipePlace.checked([0], from: nil, to: same).isEmpty)
        #expect(RecipePlace.normalized("  2   Cups\tStock ") == "2 cups stock")
    }

    @Test func readableText_whenThePageHasScriptsAndStyles_thenOnlyWhatAPersonReads() {
        let html = """
        <html><head><title> Squash &amp; Sage
        Soup </title><style>p { color: red }</style></head>
        <body><!-- nav --><script type="application/ld+json">{"a":1}</script>
        <h1>Soup</h1><p>Heat the <b>oil</b>.</p><NOSCRIPT>enable scripts</NOSCRIPT><svg><path d="M0"/></svg><p>Serve.</p></body></html>
        """
        #expect(HTMLText.readable(html, limit: 1000) == "Soup\nHeat the oil.\nServe.")
        #expect(HTMLText.readable(html, limit: 4) == "Soup")
        #expect(HTMLText.readable(html, limit: -1).isEmpty)
        #expect(HTMLText.title(in: html) == "Squash & Sage Soup")
        #expect(HTMLText.title(in: "<p>no title</p>").isEmpty)
        #expect(RecipeEnhancement.maximumPageTextLength == 12_000)
    }
}
