import Foundation
import Testing
@testable import CookingAppCore

/// Coverage for `ShoppingListItem.itemsToAdd(for:scaleFactor:existingItems:)`, the pure logic
/// behind `RecipeDetailView`'s "Add to Shopping List" button. Constructs `ShoppingListItem`/
/// `Recipe` instances directly with no `ModelContext` — the same pattern `RecipeModelTests` uses,
/// since neither type needs a real store just to exercise its own logic.
struct ShoppingListItemTests {

    @Test func addingToAnEmptyListReturnsOneItemPerIngredient() {
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Eggs", amount: "2"),
            Ingredient(name: "Milk", amount: "A splash")
        ])

        let items = ShoppingListItem.itemsToAdd(for: recipe, scaleFactor: 1, existingItems: [])

        #expect(items.count == 2)
        #expect(items.map(\.name) == ["Eggs", "Milk"])
        #expect(items.map(\.amount) == ["2", "A splash"])
        #expect(items.allSatisfy { $0.sourceRecipeTitle == recipe.title })
        #expect(items.allSatisfy { !$0.isChecked })
    }

    @Test func scalesIngredientAmountsBeforeAdding() {
        let recipe = makeRecipe(ingredients: [Ingredient(name: "Eggs", amount: "2")])

        let items = ShoppingListItem.itemsToAdd(for: recipe, scaleFactor: 2, existingItems: [])

        #expect(items.map(\.amount) == ["4"])
    }

    @Test func reAddingTheSameRecipeAtTheSameScaleProducesNoDuplicates() {
        let recipe = makeRecipe(ingredients: [Ingredient(name: "Eggs", amount: "2")])
        let firstBatch = ShoppingListItem.itemsToAdd(for: recipe, scaleFactor: 1, existingItems: [])

        let secondBatch = ShoppingListItem.itemsToAdd(for: recipe, scaleFactor: 1, existingItems: firstBatch)

        #expect(secondBatch.isEmpty)
    }

    @Test func dedupeIsCaseInsensitiveOnIngredientName() {
        let existing = [ShoppingListItem(name: "eggs", amount: "2")]
        let recipe = makeRecipe(ingredients: [Ingredient(name: "EGGS", amount: "2")])

        let items = ShoppingListItem.itemsToAdd(for: recipe, scaleFactor: 1, existingItems: existing)

        #expect(items.isEmpty)
    }

    @Test func checkedOffItemsDoNotBlockReAdding() {
        let checkedItem = ShoppingListItem(name: "Eggs", amount: "2", isChecked: true)
        let recipe = makeRecipe(ingredients: [Ingredient(name: "Eggs", amount: "2")])

        let items = ShoppingListItem.itemsToAdd(for: recipe, scaleFactor: 1, existingItems: [checkedItem])

        #expect(items.count == 1, "a checked-off item should have been bought already — re-adding for a fresh cook should be allowed")
    }

    @Test func aDifferentScaleFactorIsNotTreatedAsADuplicate() {
        let recipe = makeRecipe(ingredients: [Ingredient(name: "Eggs", amount: "2")])
        let existing = ShoppingListItem.itemsToAdd(for: recipe, scaleFactor: 1, existingItems: [])

        let doubled = ShoppingListItem.itemsToAdd(for: recipe, scaleFactor: 2, existingItems: existing)

        #expect(doubled.count == 1)
        #expect(doubled.first?.amount == "4")
    }

    @Test func ingredientsWithDifferentAmountsFromDifferentRecipesAreNotMerged() {
        let recipeA = makeRecipe(title: "Recipe A", ingredients: [Ingredient(name: "Salt", amount: "1 tsp")])
        let recipeB = makeRecipe(title: "Recipe B", ingredients: [Ingredient(name: "Salt", amount: "1/2 tsp")])

        let fromA = ShoppingListItem.itemsToAdd(for: recipeA, scaleFactor: 1, existingItems: [])
        let fromB = ShoppingListItem.itemsToAdd(for: recipeB, scaleFactor: 1, existingItems: fromA)

        #expect(fromB.count == 1, "different amounts shouldn't be silently merged or dropped")
    }

    @Test func identicalIngredientsFromDifferentRecipesAreDeduped() {
        let recipeA = makeRecipe(title: "Recipe A", ingredients: [Ingredient(name: "Salt", amount: "1 tsp")])
        let recipeB = makeRecipe(title: "Recipe B", ingredients: [Ingredient(name: "Salt", amount: "1 tsp")])

        let fromA = ShoppingListItem.itemsToAdd(for: recipeA, scaleFactor: 1, existingItems: [])
        let fromB = ShoppingListItem.itemsToAdd(for: recipeB, scaleFactor: 1, existingItems: fromA)

        #expect(fromB.isEmpty, "the same name+amount already on the list shouldn't be duplicated just because it came from a different recipe")
    }

    @Test func dedupeIgnoresSurroundingWhitespaceInNames() {
        let recipeA = makeRecipe(title: "Recipe A", ingredients: [Ingredient(name: "Salt ", amount: "1 tsp")])
        let recipeB = makeRecipe(title: "Recipe B", ingredients: [Ingredient(name: " salt", amount: "1 tsp")])

        let fromA = ShoppingListItem.itemsToAdd(for: recipeA, scaleFactor: 1, existingItems: [])
        let fromB = ShoppingListItem.itemsToAdd(for: recipeB, scaleFactor: 1, existingItems: fromA)

        #expect(fromB.isEmpty)
    }

    private func makeRecipe(title: String = "Test Recipe", ingredients: [Ingredient]) -> Recipe {
        Recipe(
            title: title,
            summary: "Test",
            soloSteps: [RecipeStep(order: 0, instruction: "Do it.", assignee: .solo, imageSystemName: "star")],
            iconSystemName: "star",
            difficulty: 1,
            soloCookTimeMinutes: 1,
            ingredients: ingredients
        )
    }
}
