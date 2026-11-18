import Foundation
import Testing
@testable import HomePadUICore

@Suite struct RecipeParserTests {
    private func page(_ json: String, type: String = "application/ld+json") -> String {
        "<html><head><script>var x = 1;</script><script type=\"\(type)\">\(json)</script></head><body></body></html>"
    }

    @Test func parse_whenPlainRecipeObject_thenReadsEveryField() throws {
        let recipe = try RecipeParser.parse(html: page(#"""
        {"@context":"https://schema.org","@type":"Recipe","name":"Butternut Squash Soup",
         "description":"A <b>cozy</b> soup &amp; more.","author":{"@type":"Person","name":"Home Cookbook"},
         "image":["https://example.com/soup.jpg"],"recipeYield":["4","4 servings"],
         "prepTime":"PT10M","cookTime":"PT25M","totalTime":"PT35M",
         "recipeIngredient":["1 squash","2 cups stock","&frac12; tsp salt"],
         "recipeInstructions":[
           {"@type":"HowToStep","name":"Oven","text":"Roast the squash for 25-30 minutes."},
           {"@type":"HowToStep","text":"Blend until smooth."}]}
        """#))
        #expect(recipe.name == "Butternut Squash Soup")
        #expect(recipe.summary == "A cozy soup & more.")
        #expect(recipe.author == "Home Cookbook")
        #expect(recipe.imageURL?.absoluteString == "https://example.com/soup.jpg")
        #expect(recipe.yield == "4 servings")
        #expect(recipe.prepTime == 600 && recipe.cookTime == 1500 && recipe.totalTime == 2100)
        #expect(recipe.displayDuration == 2100)
        #expect(recipe.ingredients == ["1 squash", "2 cups stock", "\u{00BD} tsp salt"])
        #expect(recipe.sections.count == 1 && recipe.sections[0].name == nil)
        #expect(recipe.steps.map(\.id) == [1, 2])
        #expect(recipe.steps[0].title == "Oven")
        #expect(recipe.steps[0].timer == 1500)
        #expect(recipe.steps[1].title == nil && recipe.steps[1].timer == nil)
    }

    @Test func parse_whenRecipeIsInsideGraph_thenFindsIt() throws {
        let recipe = try RecipeParser.parse(html: page(#"""
        {"@context":"https://schema.org","@graph":[
          {"@type":"WebSite","name":"Site"},
          {"@type":["Recipe","NewsArticle"],"headline":"Toast","recipeInstructions":"1. Toast the bread.\nStep 2: Butter it."}]}
        """#))
        #expect(recipe.name == "Toast")
        #expect(recipe.steps.map(\.text) == ["Toast the bread.", "Butter it."])
        #expect(recipe.ingredients.isEmpty)
        #expect(recipe.displayDuration == nil)
    }

    @Test func parse_whenTopLevelArrayAndMainEntity_thenFindsNestedRecipe() throws {
        let recipe = try RecipeParser.parse(html: page(#"""
        [{"@type":"BreadcrumbList"},{"@type":"WebPage","mainEntity":{"@type":"http://schema.org/Recipe","name":"Tea",
          "ingredients":"Water<br>Tea leaves","recipeYield":2,"image":{"@type":"ImageObject","url":"example.com/tea.png"},
          "author":[{"name":"Ada"}],"prepTime":"5 minutes","recipeInstructions":{"@type":"HowToStep","description":"Steep for 3 mins."}}}]
        """#, type: "APPLICATION/LD+JSON; charset=utf-8"))
        #expect(recipe.name == "Tea")
        #expect(recipe.ingredients == ["Water", "Tea leaves"])
        #expect(recipe.yield == "2")
        #expect(recipe.imageURL?.absoluteString == "https://example.com/tea.png")
        #expect(recipe.author == "Ada")
        #expect(recipe.prepTime == 300)
        #expect(recipe.displayDuration == 300)
        #expect(recipe.steps.first?.text == "Steep for 3 mins.")
        #expect(recipe.steps.first?.timer == 180)
    }

    @Test func parse_whenInstructionsUseSections_thenKeepsSectionNamesAndNumbersAcrossThem() throws {
        let recipe = try RecipeParser.parse(html: page(#"""
        {"@type":"schema:Recipe","name":"Pie","totalTime":"PT0M","image":[{"contentUrl":"not a url"},{"contentUrl":"https://example.com/pie.jpg"}],
         "recipeInstructions":[
          {"@type":"HowToSection","name":"Crust","itemListElement":[{"@type":"HowToStep","text":"Mix flour."},{"@type":"HowToStep","text":"Chill 1 hour and 30 minutes."}]},
          {"@type":"HowToSection","name":"Filling","itemListElement":[{"@type":"HowToStep","name":"Cook apples until soft","text":"Cook apples until soft, about 10 min."}]},
          {"@type":"ItemList","itemListElement":["Bake.", 42]},
          "Cool completely."]}
        """#))
        #expect(recipe.sections.map(\.name) == ["Crust", "Filling", nil])
        #expect(recipe.sections.map { $0.steps.map(\.id) } == [[1, 2], [3], [4, 5]])
        #expect(recipe.steps[1].timer == 5400)
        #expect(recipe.steps[2].title == nil)
        #expect(recipe.steps[3].text == "Bake.")
        #expect(recipe.totalTime == nil)
        #expect(recipe.imageURL?.absoluteString == "https://example.com/pie.jpg")
    }

    @Test func parse_whenTextHasMarkupAndEntities_thenPlainText() throws {
        let recipe = try RecipeParser.parse(html: page(#"""
        {"@type":"Recipe","name":"Cr&egrave;me &#8211; br&#xFB;l&eacute;e &unknown; &#1; 5 &lt; 6 &","recipeYield":{"@value":"6"},
         "recipeInstructions":[{"text":"<p>Heat&nbsp;cream to 80&deg;C.</p><p>Whisk  yolks\u2014gently.</p>"}]}
        """#))
        #expect(recipe.name == "Cr\u{00E8}me - br\u{00FB}l\u{00E9}e &unknown; &#1; 5 < 6 &")
        #expect(recipe.yield == "6")
        #expect(recipe.steps[0].text == "Heat cream to 80\u{00B0}C. Whisk yolks-gently.")
    }

    @Test func parse_whenPageHasNoStructuredData_thenTypedError() {
        #expect(throws: RecipeParseError.noStructuredData) { try RecipeParser.parse(html: "<html><script>alert(1)</script></html>") }
        #expect(throws: RecipeParseError.noStructuredData) { try RecipeParser.parse(html: "<script type=\"application/ld+json\">{}") }
        #expect(throws: RecipeParseError.noStructuredData) { try RecipeParser.parse(html: "<script type=\"application/ld+json\"") }
    }

    @Test func parse_whenStructuredDataHasNoRecipe_thenTypedError() {
        #expect(throws: RecipeParseError.noRecipe) { try RecipeParser.parse(html: page(#"{"@type":"Article","name":"News"}"#)) }
        #expect(throws: RecipeParseError.noRecipe) { try RecipeParser.parse(html: page("{ this is not json")) }
        #expect(throws: RecipeParseError.noRecipe) { try RecipeParser.parse(html: page(#""just a string""#)) }
        #expect(throws: RecipeParseError.noRecipe) { try RecipeParser.parse(html: page(#"{"@type":7}"#)) }
    }

    @Test func parse_whenRecipeLacksNameOrSteps_thenIncomplete() {
        #expect(throws: RecipeParseError.incompleteRecipe) { try RecipeParser.parse(html: page(#"{"@type":"Recipe","name":"Empty"}"#)) }
        #expect(throws: RecipeParseError.incompleteRecipe) { try RecipeParser.parse(html: page(#"{"@type":"Recipe","recipeInstructions":["Stir."]}"#)) }
        #expect(throws: RecipeParseError.incompleteRecipe) { try RecipeParser.parse(html: page(#"{"@type":"Recipe","name":"  ","recipeInstructions":[{"@type":"HowToStep"}, true]}"#)) }
    }

    @Test func parse_whenPageTooLargeOrTooDeep_thenRejected() {
        let huge = String(repeating: "a", count: RecipeParser.maximumBytes + 1)
        #expect(throws: RecipeParseError.pageTooLarge) { try RecipeParser.parse(html: huge) }
        let deepGraph = String(repeating: #"{"@graph":"#, count: 14) + #"{"@type":"Recipe","name":"Deep","recipeInstructions":"Stir."}"# + String(repeating: "}", count: 14)
        #expect(throws: RecipeParseError.noRecipe) { try RecipeParser.parse(html: page(deepGraph)) }
        let deepSteps = String(repeating: "[", count: 14) + "\"Stir.\"" + String(repeating: "]", count: 14)
        #expect(throws: RecipeParseError.incompleteRecipe) { try RecipeParser.parse(html: page(#"{"@type":"Recipe","name":"Deep","recipeInstructions":"# + deepSteps + "}")) }
    }

    @Test func parse_whenScriptBlockContainsCode_thenNothingRunsAndTextIsInert() throws {
        let recipe = try RecipeParser.parse(html: page(#"""
        {"@type":"Recipe","name":"<script>alert('x')<\/script>Safe","recipeInstructions":["<img src=x onerror=alert(1)>Mix &lt;script&gt;."]}
        """#))
        #expect(recipe.name == "alert('x')Safe")
        #expect(recipe.steps[0].text == "Mix <script>.")
    }

    @Test func parse_whenSeveralBlocksAndFirstRecipeIsIncomplete_thenUsesTheCompleteOne() throws {
        let html = page(#"{"@type":"Recipe","name":"Stub"}"#) + page(#"{"@type":"Recipe","name":"Real","recipeInstructions":["Go."]}"#)
        #expect(try RecipeParser.parse(html: html).name == "Real")
    }

    @Test func isoDuration_whenValid_thenSeconds() {
        #expect(ISO8601Duration.seconds(from: "PT1H30M") == 5400)
        #expect(ISO8601Duration.seconds(from: " pt45s ") == 45)
        #expect(ISO8601Duration.seconds(from: "P1DT2H") == 93_600)
        #expect(ISO8601Duration.seconds(from: "P1W") == 604_800)
        #expect(ISO8601Duration.seconds(from: "PT1,5H") == 5400)
        #expect(ISO8601Duration.seconds(from: "PT0.5M") == 30)
    }

    @Test func isoDuration_whenMalformed_thenNil() {
        for text in ["", "1H", "P", "PT", "PT5", "P1Y", "P1M", "PTT5M", "PT5MT", "PT1H5X", "P5H", "PT.M", "PT5M3"] {
            #expect(ISO8601Duration.seconds(from: text) == nil, "\(text)")
        }
    }

    @Test func timerDuration_whenStepMentionsTime_thenFirstDurationOnly() {
        #expect(RecipeTimers.duration(in: "Simmer for 1 hour and 30 minutes, then rest 5 minutes.") == 5400)
        #expect(RecipeTimers.duration(in: "Bake 25 to 30 mins") == 1500)
        #expect(RecipeTimers.duration(in: "Rest 90 seconds") == 90)
        #expect(RecipeTimers.duration(in: "Cook 1.5 hrs, 10 min") == 6000)
        #expect(RecipeTimers.duration(in: "Boil 2 Minutes. Drain. Wait 3 minutes.") == 120)
        #expect(RecipeTimers.duration(in: "Add 2 cups of flour") == nil)
        #expect(RecipeTimers.duration(in: "Wait 0 minutes") == nil)
        #expect(RecipeTimers.duration(in: "Cure for 100 hours") == TimerEngine.maximumDuration)
    }

    @Test func normalizedURL_whenWebAddress_thenAcceptedOtherwiseRejected() {
        #expect(RecipeSourcePolicy.normalizedURL(from: " example.com/soup ")?.absoluteString == "https://example.com/soup")
        #expect(RecipeSourcePolicy.normalizedURL(from: "http://example.com")?.scheme == "http")
        #expect(RecipeSourcePolicy.normalizedURL(from: "") == nil)
        #expect(RecipeSourcePolicy.normalizedURL(from: "two words.com") == nil)
        #expect(RecipeSourcePolicy.normalizedURL(from: "file:///etc/passwd") == nil)
        #expect(RecipeSourcePolicy.normalizedURL(from: "javascript://example.com/alert(1)") == nil)
        #expect(RecipeSourcePolicy.normalizedURL(from: "localhost") == nil)
        #expect(RecipeSourcePolicy.normalizedURL(from: "https://") == nil)
    }

    @Test func htmlText_whenEntityHasNoSemicolonNearby_thenLeftAlone() {
        #expect(HTMLText.plain("Salt &amp pepper; fish &amp; chips") == "Salt &amp pepper; fish & chips")
        #expect(HTMLText.plain("A&#x41;&#65;&#xZZ;&#99999999999;&#1114112;") == "AAA&#xZZ;&#99999999999;&#1114112;")
        #expect(HTMLText.plain("one<br/>two<BR>three</li>  \n\n four") == "one\ntwo\nthree\nfour")
        #expect(HTMLText.plain("&hellip;&ndash;&mdash;&times;&rsquo;") == "...--\u{00D7}\u{2019}")
        #expect(HTMLText.strippingStepNumber("2) Stir") == "Stir")
        #expect(HTMLText.strippingStepNumber("350 degrees") == "350 degrees")
    }
}
