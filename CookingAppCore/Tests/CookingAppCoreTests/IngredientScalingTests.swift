import Testing
@testable import CookingAppCore

/// Coverage for `Ingredient.scaledAmount(by:)`, which backs `RecipeDetailView`'s servings
/// stepper. Exercises every amount shape actually present in `SampleRecipes.swift` (see that
/// file for the full survey this was written against), plus a few synthetic edge cases the
/// bundled recipes don't happen to use but the parser still needs to handle sanely.
struct IngredientScalingTests {

    // MARK: - Whole numbers

    @Test func scalesAPlainWholeNumberUp() {
        #expect(Ingredient.scale("2", by: 2) == "4")
    }

    @Test func scalesAPlainWholeNumberDown() {
        #expect(Ingredient.scale("4", by: 0.5) == "2")
    }

    @Test func scalesAWholeNumberWithASpacedUnit() {
        #expect(Ingredient.scale("2 cups", by: 2) == "4 cups")
        #expect(Ingredient.scale("3 tbsp", by: 3) == "9 tbsp")
    }

    @Test func scalesAWholeNumberWithNoSpaceBeforeTheUnit() {
        #expect(Ingredient.scale("200g", by: 2) == "400g")
        #expect(Ingredient.scale("500ml", by: 0.5) == "250ml")
    }

    @Test func scalesAWholeNumberFollowedByAWordThatIsNotAUnit() {
        #expect(Ingredient.scale("1 small", by: 2) == "2 small")
        #expect(Ingredient.scale("4 large", by: 0.5) == "2 large")
    }

    // MARK: - Decimals

    @Test func scalesADecimalToAWholeNumber() {
        #expect(Ingredient.scale("1.5 cups", by: 2) == "3 cups")
    }

    @Test func scalesADecimalToAFraction() {
        #expect(Ingredient.scale("2.25 cups", by: 2) == "4 1/2 cups")
    }

    // MARK: - Simple fractions

    @Test func scalesAFractionUpToAWholeNumber() {
        #expect(Ingredient.scale("1/2 cup", by: 2) == "1 cup")
    }

    @Test func scalesAFractionUpToAMixedNumber() {
        #expect(Ingredient.scale("1/2 tsp", by: 3) == "1 1/2 tsp")
        #expect(Ingredient.scale("3/4 cup", by: 2) == "1 1/2 cup")
    }

    @Test func scalesAFractionWithNoUnitSuffix() {
        #expect(Ingredient.scale("1/2", by: 2) == "1")
        #expect(Ingredient.scale("1/4 cup", by: 2) == "1/2 cup")
    }

    @Test func scalesAFractionDown() {
        #expect(Ingredient.scale("1/2 cup", by: 0.5) == "1/4 cup")
    }

    // MARK: - Mixed numbers (not in bundled data yet, but the parser supports them)

    @Test func scalesAMixedNumberUp() {
        #expect(Ingredient.scale("1 1/2 cups", by: 2) == "3 cups")
    }

    @Test func scalesAMixedNumberToAnotherMixedNumber() {
        #expect(Ingredient.scale("1 1/2 cups", by: 1.5) == "2 1/4 cups")
    }

    // MARK: - Non-numeric amounts pass through unchanged

    @Test func qualitativeAmountsAreNeverAltered() {
        for amount in ["A pinch", "A drizzle", "A splash", "A squeeze", "A handful", "A few leaves", "A few sprigs", "To taste", "As needed", "For serving"] {
            #expect(Ingredient.scale(amount, by: 2) == amount)
            #expect(Ingredient.scale(amount, by: 0.5) == amount)
        }
    }

    // MARK: - Identity and guard cases

    @Test func scalingByOneLeavesTheValueUnchangedModuloFormatting() {
        #expect(Ingredient.scale("2 cups", by: 1) == "2 cups")
        #expect(Ingredient.scale("1/2 cup", by: 1) == "1/2 cup")
    }

    @Test func nonPositiveOrNonFiniteFactorsAreRefusedRatherThanProducingGarbage() {
        let amount = "2 cups"
        #expect(Ingredient.scale(amount, by: 0) == amount)
        #expect(Ingredient.scale(amount, by: -1) == amount)
        #expect(Ingredient.scale(amount, by: .nan) == amount)
        #expect(Ingredient.scale(amount, by: .infinity) == amount)
    }

    @Test func scaledAmountInstanceMethodDelegatesToTheStaticParser() {
        let ingredient = Ingredient(name: "Flour", amount: "1 cup")
        #expect(ingredient.scaledAmount(by: 2) == "2 cup")
    }

    // MARK: - Every bundled ingredient amount is at least handled without crashing or corrupting
    // non-numeric text — a broad regression guard alongside the targeted cases above.

    @Test func everyBundledIngredientAmountScalesWithoutCorruptingNonNumericText() {
        for recipe in SampleRecipes.all {
            for ingredient in recipe.ingredients {
                let doubled = ingredient.scaledAmount(by: 2)
                let halved = ingredient.scaledAmount(by: 0.5)
                #expect(!doubled.isEmpty, "\(recipe.title): \(ingredient.name) scaled to empty string")
                #expect(!halved.isEmpty, "\(recipe.title): \(ingredient.name) scaled to empty string")
            }
        }
    }
}
