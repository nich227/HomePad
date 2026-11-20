import Foundation
import HomePadAssistant
import HomePadAssistantCore
import HomePadUICore

/// Connects the Recipes reader to the Assistant's recipe formatter. The reader hands over what
/// it parsed from the page, and gets back the same recipe as short, titled steps. The formatter
/// has already checked every amount and ingredient against the page.
@MainActor
final class HubRecipeEnhancer: RecipeEnhancing {
    private let formatter: any RecipeFormatting

    init(formatter: any RecipeFormatting) {
        self.formatter = formatter
    }

    func enhance(recipe: Recipe?, pageText: String, title: String) async -> Recipe? {
        let draft = RecipeDraft(
            name: recipe?.name ?? title,
            summary: recipe?.summary ?? "",
            yield: recipe?.yield ?? "",
            totalTime: recipe?.displayDuration,
            ingredients: recipe?.ingredients ?? [],
            steps: recipe?.steps.map(\.text) ?? []
        )
        let outcome = await formatter.format(draft: draft, pageText: pageText)
        if let formatted = outcome.formatted {
            return Self.recipe(from: formatted, pageSteps: recipe?.steps ?? [])
        }
        // The page had no recipe data, but the model found which lines are the recipe. The
        // text is the page's own.
        if recipe == nil, outcome.originalWasLocatedByModel, outcome.original.hasRecipe {
            return Self.recipe(from: outcome.original)
        }
        return nil
    }

    static func recipe(from formatted: FormattedRecipe, pageSteps: [RecipeStep]) -> Recipe {
        let steps = formatted.steps.map { step in
            RecipeStep(
                id: step.id,
                title: step.title.isEmpty ? nil : step.title,
                text: step.instruction,
                timer: step.timerSeconds.map(TimeInterval.init),
                ingredients: step.ingredients,
                // Lets the reader stay on the step the cook was reading when the tidied recipe arrives.
                sourceStepID: pageSteps.indices.contains(step.sourceStepNumber - 1) ? pageSteps[step.sourceStepNumber - 1].id : nil
            )
        }
        return Recipe(
            name: formatted.name,
            summary: formatted.summary.isEmpty ? nil : formatted.summary,
            yield: formatted.yield.isEmpty ? nil : formatted.yield,
            totalTime: formatted.totalTime,
            ingredients: formatted.ingredients,
            sections: [RecipeSection(steps: steps)]
        )
    }

    static func recipe(from draft: RecipeDraft) -> Recipe {
        let steps = draft.steps.enumerated().map { index, text in
            RecipeStep(id: index + 1, text: text)
        }
        return Recipe(
            name: draft.name,
            summary: draft.summary.isEmpty ? nil : draft.summary,
            yield: draft.yield.isEmpty ? nil : draft.yield,
            totalTime: draft.totalTime,
            ingredients: draft.ingredients,
            sections: [RecipeSection(steps: steps)]
        )
    }
}
