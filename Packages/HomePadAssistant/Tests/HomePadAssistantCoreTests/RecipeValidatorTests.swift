import Foundation
import Testing
@testable import HomePadAssistantCore

private func part(_ instruction: String, title: String = "", timer: Int = 0, step: Int = 1) -> RecipeModelStep {
    RecipeModelStep(sourceStep: step, title: title, instruction: instruction, timerSeconds: timer)
}

private func check(_ source: String, _ parts: [String], vocabulary: Set<String> = []) -> [String]? {
    RecipeValidator.step(parts.map { part($0) }, source: source, vocabulary: vocabulary)?.map(\.instruction)
}

@Suite struct RecipeIngredientValidationTests {
    @Test(arguments: [
        ("Flour, all-purpose, 2 cups", "2 cups all-purpose flour"),
        ("1/2 tsp salt", "\u{00BD} teaspoon salt"),
        ("2 tbsp butter, softened", "2 tablespoons softened butter"),
        ("two eggs, beaten", "2 beaten eggs"),
        ("1 (15-ounce) can black beans", "1 can (15 oz) black beans"),
        ("a cup of sugar", "1 cup sugar"),
        ("Salt, to taste", "Salt to taste"),
    ])
    func ingredientLine_whenOnlyReorderedOrRespelled_thenPasses(first: String, second: String) {
        #expect(RecipeValidator.ingredientLine(second, source: first) == second)
    }

    @Test(arguments: [
        ("1 cup sugar", "2 cups sugar"),
        ("1 tsp salt", "1 tbsp salt"),
        ("1 cup sugar", "sugar"),
        ("1 cup sugar", "1 cup sugar, 1 cup"),
        ("1 lb ground beef", "16 oz ground beef"),
        ("1/3 cup oil", "1/2 cup oil"),
        ("2 cups flour", "2 1/2 cups flour"),
    ])
    func ingredientLine_whenAnAmountChanges_thenFails(first: String, second: String) {
        #expect(RecipeValidator.ingredientLine(second, source: first) == nil)
    }

    @Test(arguments: [
        ("1 cup sugar", "1 cup brown sugar"),
        ("1 cup unsalted butter", "1 cup butter"),
        ("1 cup milk", "1 cup cream"),
        ("2 eggs", "2 eggs and 1 pinch salt"),
        ("1 cup sugar", "1 cup"),
        ("Salt and pepper", "Salt"),
    ])
    func ingredientLine_whenAWordIsAddedDroppedOrSwapped_thenFails(first: String, second: String) {
        #expect(RecipeValidator.ingredientLine(second, source: first) == nil)
    }

    @Test func ingredientLine_whenNotPlainOrOutOfBounds_thenFails() {
        #expect(RecipeValidator.ingredientLine("**1 cup** sugar", source: "1 cup sugar") == nil)
        #expect(RecipeValidator.ingredientLine("1 cup sugar https://example.com", source: "1 cup sugar") == nil)
        #expect(RecipeValidator.ingredientLine("   ", source: "1 cup sugar") == nil)
        let long = "1 cup sugar" + String(repeating: " sugar", count: 40)
        #expect(RecipeValidator.ingredientLine(long, source: "1 cup sugar") == nil)
        #expect(RecipeValidator.ingredientLine("1 cup\n sugar", source: "1 cup sugar") == "1 cup sugar")
    }

    @Test func ingredientLines_whenAnswered_thenOnlyCheckedLinesUnderNumbersThatWereSentOnce() {
        let recipe = RecipeDraft(ingredients: ["Flour, 2 cups", "1 egg", "Salt, 1 tsp", "1 cup milk"])
        let request = RecipePrompt.ingredients(recipe, indices: [0, 1, 2, 3])
        let answer = [
            RecipeModelLine(number: 1, text: "2 cups flour"),
            RecipeModelLine(number: 2, text: "2 eggs"),
            RecipeModelLine(number: 3, text: "1 tsp salt"),
            RecipeModelLine(number: 3, text: "1 tsp salt"),
            RecipeModelLine(number: 9, text: "1 cup cream"),
        ]
        #expect(RecipeValidator.ingredientLines(answer, request: request) == [1: "2 cups flour"])
    }

    @Test func summary_whenItUsesTheRecipesWordsAndAmounts_thenPasses() {
        let recipe = RecipeDraft(name: "Lemon Bars", summary: "Tart lemon filling on a buttery shortbread crust.", ingredients: ["2 lemons", "1 cup butter"])
        #expect(RecipeValidator.summary("Buttery shortbread with a tart lemon filling. Uses 2 lemons.", recipe: recipe) == "Buttery shortbread with a tart lemon filling. Uses 2 lemons.")
    }

    @Test func summary_whenItInventsOrRunsLong_thenFails() {
        let recipe = RecipeDraft(name: "Lemon Bars", summary: "Tart lemon filling on a buttery shortbread crust.", ingredients: ["2 lemons", "1 cup butter"])
        #expect(RecipeValidator.summary("Lemon bars that serve 8 people.", recipe: recipe) == nil)
        #expect(RecipeValidator.summary("A spicy chicken curry with rice and peas.", recipe: recipe) == nil)
        #expect(RecipeValidator.summary("Tart. Lemon. Bars.", recipe: recipe) == nil)
        #expect(RecipeValidator.summary("!!!", recipe: recipe) == nil)
        #expect(RecipeValidator.summary("", recipe: recipe) == nil)
        #expect(RecipeValidator.summary("Tart <i>lemon</i> bars.", recipe: recipe) == nil)
        #expect(RecipeValidator.summary(String(repeating: "lemon ", count: 60), recipe: recipe) == nil)
    }
}

@Suite struct RecipeStepValidationTests {
    static let source = "Preheat the oven to 350\u{00B0}F. In a large bowl, whisk together 2 cups flour, 1 teaspoon baking soda, and 1/2 teaspoon salt. Bake for 10 to 12 minutes, until golden."
    static let faithful = [
        "Preheat the oven to 350 degrees F.",
        "In a large bowl, whisk together 2 cups flour, 1 tsp baking soda, and \u{00BD} tsp salt.",
        "Bake for 10-12 min, until golden.",
    ]
    static let vocabulary: Set<String> = Set(["flour", "soda", "salt"].map(RecipeWords.stem))

    @Test func step_whenSplitFaithfully_thenEveryPartPasses() {
        #expect(check(Self.source, Self.faithful, vocabulary: Self.vocabulary) == Self.faithful)
    }

    @Test(arguments: [
        (0, "Preheat the oven to 375 degrees F."),
        (0, "Preheat the oven to 350 degrees C."),
        (0, "Preheat the oven to 350 degrees."),
        (1, "In a large bowl, whisk together 3 cups flour, 1 tsp baking soda, and \u{00BD} tsp salt."),
        (1, "In a large bowl, whisk together 2 cups flour, 1 tbsp baking soda, and \u{00BD} tsp salt."),
        (1, "In a large bowl, whisk together 2 cups flour, 1 tsp baking soda, and 1 tsp salt."),
        (2, "Bake for 10 to 20 minutes, until golden."),
        (2, "Bake for 10 to 12 hours, until golden."),
        (2, "Bake for 12 minutes, until golden."),
    ])
    func step_whenAnAmountTemperatureOrTimeChanges_thenFails(index: Int, text: String) {
        var parts = Self.faithful
        parts[index] = text
        #expect(check(Self.source, parts, vocabulary: Self.vocabulary) == nil)
    }

    @Test func step_whenAnAmountIsDroppedAddedOrRepeated_thenFails() {
        var dropped = Self.faithful
        dropped[0] = "Preheat the oven."
        #expect(check(Self.source, dropped) == nil)
        var added = Self.faithful
        added[2] = "Bake for 10 to 12 minutes, until golden. Cool 5 minutes."
        #expect(check(Self.source, added) == nil)
        var repeated = Self.faithful
        repeated[2] = "Bake in the 350 degrees F oven for 10 to 12 minutes, until golden."
        #expect(check(Self.source, repeated) == nil)
    }

    @Test func step_whenAmountsTradePlaces_thenFails() {
        let source = "Whisk 1 cup flour and 2 cups sugar."
        #expect(check(source, ["Whisk 1 cup flour and 2 cups sugar."]) != nil)
        #expect(check(source, ["Whisk 2 cups flour and 1 cup sugar."]) == nil)
        #expect(check(source, ["Whisk 1 cup sugar and 2 cups flour."]) == nil)
    }

    @Test func step_whenTimesTradeActions_thenFails() {
        let source = "Bake 10 minutes. Broil 2 minutes."
        #expect(check(source, ["Bake 10 minutes.", "Broil 2 minutes."]) != nil)
        #expect(check(source, ["Broil 10 minutes.", "Bake 2 minutes."]) == nil)
        #expect(check("Bake 10 minutes then broil 2 minutes.", ["Broil 10 minutes then bake 2 minutes."]) == nil)
    }

    @Test func step_whenATimeMovesWithinItsSentence_thenPasses() {
        let source = "Cook, stirring occasionally, until the onions are soft, about 8 minutes."
        #expect(check(source, ["Cook until the onions are soft, about 8 minutes.", "Stir occasionally."]) != nil)
        #expect(check("Simmer the sauce for 20 minutes.", ["Simmer the sauce.", "Cook 20 minutes."]) == nil)
        #expect(check("Simmer the sauce for 20 minutes.", ["Simmer the sauce for 20 minutes."]) != nil)
    }

    @Test func step_whenAnIngredientAppearsThatTheStepDoesNotHave_thenFails() {
        #expect(check("Whisk the eggs and sugar.", ["Whisk the eggs, sugar, and vanilla."]) == nil)
        #expect(check("Whisk the eggs and sugar.", ["Whisk the eggs and sugar.", "Season with salt."]) == nil)
        #expect(check("Whisk the eggs and sugar.", ["Combine the eggs and sugar.", "Whisk."]) != nil)
    }

    @Test func step_whenAnIngredientOfTheStepIsLost_thenFails() {
        let source = "Add the flour, the sugar, the cocoa, the butter, the milk, and the salt to the bowl."
        let vocabulary: Set<String> = Set(["flour", "sugar", "cocoa", "butter", "milk", "salt"].map(RecipeWords.stem))
        #expect(check(source, ["Add the flour, sugar, cocoa, butter, and milk to the bowl."], vocabulary: vocabulary) == nil)
        #expect(check(source, ["Add the flour, sugar, cocoa, butter, and milk to the bowl."], vocabulary: []) != nil)
        #expect(check(source, ["Add the flour, sugar, cocoa, butter, milk, and salt to the bowl."], vocabulary: vocabulary) != nil)
    }

    @Test func step_whenAWordThatReversesTheStepIsLost_thenFails() {
        let source = "Fold in the berries gently with a wide spatula and do not overmix the batter."
        #expect(check(source, ["Fold in the berries gently with a wide spatula.", "Do overmix the batter."]) == nil)
        #expect(check(source, ["Fold in the berries gently with a wide spatula.", "Do not overmix the batter."]) != nil)
    }

    @Test func step_whenTheHeatOrTheLidIsLost_thenFails() {
        let source = "Cook the onions over low heat until soft and golden brown, then simmer covered."
        #expect(check(source, ["Cook the onions over heat until soft and golden brown, then simmer covered."]) == nil)
        #expect(check(source, ["Cook the onions over low heat until soft and golden brown, then simmer."]) == nil)
        #expect(check(source, ["Cook the onions over low heat until soft and golden brown.", "Simmer covered."]) != nil)
    }

    @Test func step_whenASentenceIsDropped_thenFails() {
        let source = "Whisk the eggs. Let the custard cool completely before slicing."
        #expect(check(source, ["Whisk the eggs."]) == nil)
        #expect(check(source, ["Whisk the eggs.", "Let the custard cool before slicing."]) != nil)
        #expect(check(source, ["Whisk the eggs.", "Cool before slicing."]) == nil)
    }

    @Test func step_whenPartsAreMissingTooManyTooLongOrNotPlain_thenFails() {
        let source = "Mix. Mix. Mix. Mix. Mix. Mix. Mix."
        #expect(RecipeValidator.step([], source: source, vocabulary: []) == nil)
        #expect(check(source, Array(repeating: "Mix.", count: 7)) == nil)
        #expect(check(source, Array(repeating: "Mix.", count: 6)) != nil)
        #expect(check(source, ["Mix. Mix. Mix. Mix."]) == nil)
        #expect(check(source, ["Mix " + String(repeating: "mix ", count: 100)]) == nil)
        #expect(check(source, ["**Mix**."]) == nil)
        #expect(check(source, ["Mix. See example.com"]) == nil)
        #expect(check(source, [" "]) == nil)
    }

    @Test func steps_whenTheAnswerReordersOrNamesAnUnknownStep_thenAllOfItIsRefused() {
        let recipe = RecipeDraft(steps: ["Mix the batter.", "Bake 10 minutes."])
        let request = RecipePrompt.steps(recipe, indices: [0, 1])
        let good = [part("Mix the batter.", step: 1), part("Bake 10 minutes.", step: 2)]
        #expect(RecipeValidator.steps(good, request: request, vocabulary: []).keys.sorted() == [1, 2])
        #expect(RecipeValidator.steps(good.reversed(), request: request, vocabulary: []).isEmpty)
        #expect(RecipeValidator.steps(good + [part("Cool.", step: 3)], request: request, vocabulary: []).isEmpty)
        #expect(RecipeValidator.steps([], request: request, vocabulary: []).isEmpty)
    }

    @Test func steps_whenOneStepFails_thenOnlyTheOthersCome() {
        let recipe = RecipeDraft(steps: ["Mix the batter.", "Bake 10 minutes.", "Cool."])
        let request = RecipePrompt.steps(recipe, indices: [0, 1, 2])
        let answer = [part("Mix the batter.", step: 1), part("Bake 15 minutes.", step: 2)]
        let checked = RecipeValidator.steps(answer, request: request, vocabulary: [])
        #expect(checked.keys.sorted() == [1])
        #expect(checked[1] == [RecipeCheckedPart(title: "", instruction: "Mix the batter.", timerSeconds: nil)])
    }

    @Test func title_whenShortAndFromTheStepsWords_thenKeptOtherwiseEmpty() {
        let source = "Melt the butter in a pan until golden brown, about 5 minutes."
        func title(_ text: String) -> String? {
            RecipeValidator.step([part(source, title: text)], source: source, vocabulary: [])?.first?.title
        }
        #expect(title("Brown the butter.") == "Brown the butter")
        #expect(title("Melt butter 5 minutes") == "Melt butter 5 minutes")
        #expect(title("Make the brown butter:") == "Make the brown butter")
        #expect(title("Caramelize the sugar") == "")
        #expect(title("Melt butter 10 minutes") == "")
        #expect(title("Melt the butter in a pan until golden") == "")
        #expect(title("**Brown** butter") == "")
        #expect(title("") == "")
        #expect(title(String(repeating: "butter", count: 10)) == "")
    }

    @Test func timer_whenTheModelsTimeIsStated_thenKeptOtherwiseTheOneStatedTime() {
        func timer(_ text: String, _ candidate: Int) -> Int? {
            RecipeValidator.timer(candidate, instruction: RecipeScan(text))
        }
        #expect(timer("Bake 8 to 10 minutes.", 600) == 600)
        #expect(timer("Bake 8 to 10 minutes.", 480) == 480)
        #expect(timer("Bake 8 to 10 minutes.", 900) == 480)
        #expect(timer("Bake 8 to 10 minutes.", 0) == 480)
        #expect(timer("Sear 2 minutes, then roast 1 hour.", 3_600) == 3_600)
        #expect(timer("Sear 2 minutes, then roast 1 hour.", 0) == nil)
        #expect(timer("Stir well.", 300) == nil)
        #expect(timer("Stir well.", -5) == nil)
    }
}

@Suite struct RecipeLocationTests {
    static let page = RecipePage(
        lines: ["Best Cookies", "Makes 24", "Ingredients", "1 cup flour", "2 eggs", "Salt", "Instructions", "1. Mix everything.", "2. Bake 10 minutes."],
        wasCut: false
    )
    static let location = RecipeModelLocation(nameLine: 1, yieldLine: 2, firstIngredientLine: 3, lastIngredientLine: 6, firstStepLine: 7, lastStepLine: 9)

    @Test func located_whenTheLinesMakeARecipe_thenCopiedWithoutHeadingsAndLabels() {
        let recipe = RecipeValidator.located(Self.location, in: Self.page, filling: RecipeDraft())
        #expect(recipe == RecipeDraft(
            name: "Best Cookies",
            yield: "Makes 24",
            ingredients: ["1 cup flour", "2 eggs", "Salt"],
            steps: ["Mix everything.", "Bake 10 minutes."]
        ))
    }

    @Test func located_whenTheDraftHasAPart_thenTheDraftsPartWins() {
        let draft = RecipeDraft(name: "Grandma's Cookies", yield: "2 dozen", ingredients: ["3 cups flour"])
        let recipe = RecipeValidator.located(RecipeModelLocation(firstStepLine: 8, lastStepLine: 9), in: Self.page, filling: draft)
        #expect(recipe == RecipeDraft(name: "Grandma's Cookies", yield: "2 dozen", ingredients: ["3 cups flour"], steps: ["Mix everything.", "Bake 10 minutes."]))
        let steps = RecipeDraft(steps: ["Stir."])
        let filled = RecipeValidator.located(RecipeModelLocation(firstIngredientLine: 4, lastIngredientLine: 5), in: Self.page, filling: steps)
        #expect(filled == RecipeDraft(ingredients: ["1 cup flour", "2 eggs"], steps: ["Stir."]))
    }

    @Test func located_whenTheNameOrYieldLineIsInsideTheRecipeOrOffThePage_thenLeftEmpty() {
        var location = Self.location
        location.nameLine = 4
        location.yieldLine = 40
        let recipe = RecipeValidator.located(location, in: Self.page, filling: RecipeDraft())
        #expect(recipe?.name == "")
        #expect(recipe?.yield == "")
        location.nameLine = 0
        #expect(RecipeValidator.located(location, in: Self.page, filling: RecipeDraft())?.name == "")
    }

    @Test(arguments: [
        RecipeModelLocation(),
        RecipeModelLocation(firstIngredientLine: 4, lastIngredientLine: 6),
        RecipeModelLocation(firstStepLine: 8, lastStepLine: 9),
        RecipeModelLocation(firstIngredientLine: 4, lastIngredientLine: 8, firstStepLine: 8, lastStepLine: 9),
        RecipeModelLocation(firstIngredientLine: 6, lastIngredientLine: 4, firstStepLine: 8, lastStepLine: 9),
        RecipeModelLocation(firstIngredientLine: 4, lastIngredientLine: 6, firstStepLine: 8, lastStepLine: 12),
        RecipeModelLocation(firstIngredientLine: 0, lastIngredientLine: 6, firstStepLine: 8, lastStepLine: 9),
        RecipeModelLocation(firstIngredientLine: 1, lastIngredientLine: 1, firstStepLine: 8, lastStepLine: 9),
        RecipeModelLocation(firstIngredientLine: 3, lastIngredientLine: 3, firstStepLine: 8, lastStepLine: 9),
        RecipeModelLocation(firstIngredientLine: 4, lastIngredientLine: 6, firstStepLine: 7, lastStepLine: 7),
    ])
    func located_whenTheLinesDoNotMakeARecipe_thenNil(location: RecipeModelLocation) {
        #expect(RecipeValidator.located(location, in: Self.page, filling: RecipeDraft()) == nil)
    }
}

@Suite struct RecipeIngredientIndexTests {
    static let sources = [
        "1 cup (2 sticks) unsalted butter, softened",
        "1 cup packed dark brown sugar",
        "1/2 cup granulated sugar",
        "2 tablespoons olive oil",
        "1 cup vegetable oil",
        "2 cloves garlic, minced",
        "Salt, to taste",
        "1 pinch",
    ]
    static let index = RecipeIngredientIndex(lines: sources.map { "Shown: \($0)" }, sources: sources)

    @Test func lines_whenAStepSaysAnIngredientsMainName_thenThatLineInListOrder() {
        #expect(Self.index.lines(usedBy: "Mince the garlic and melt the butter.") == ["Shown: \(Self.sources[0])", "Shown: \(Self.sources[5])"])
        #expect(Self.index.lines(usedBy: "Cook until golden brown.") == [])
        #expect(Self.index.lines(usedBy: "Season with salt.") == ["Shown: \(Self.sources[6])"])
        #expect(Self.index.lines(usedBy: "Stir.") == [])
    }

    @Test func lines_whenTwoIngredientsShareAMainName_thenTheOneTheStepDescribesOrBoth() {
        #expect(Self.index.lines(usedBy: "Heat the oil.") == ["Shown: \(Self.sources[3])", "Shown: \(Self.sources[4])"])
        #expect(Self.index.lines(usedBy: "Heat the olive oil.") == ["Shown: \(Self.sources[3])"])
        #expect(Self.index.lines(usedBy: "Whisk the brown sugar and granulated sugar.") == ["Shown: \(Self.sources[1])", "Shown: \(Self.sources[2])"])
    }

    @Test func lines_whenAStepNamesMany_thenAtMostTheLimit() {
        let sources = (1...12).map { "1 cup spice\($0)x" }
        let index = RecipeIngredientIndex(lines: sources, sources: sources)
        let step = "Add " + (1...12).map { "spice\($0)x" }.joined(separator: ", ")
        #expect(index.lines(usedBy: step).count == RecipeLimits.maxStepIngredients)
    }

    @Test func vocabulary_whenBuilt_thenTheWordsThatNameIngredientsWithoutDescriptions() {
        let expected = ["unsalted", "butter", "dark", "brown", "sugar", "granulated", "olive", "oil", "vegetable", "garlic", "salt"]
        #expect(Self.index.vocabulary == Set(expected.map(RecipeWords.stem)))
    }
}
