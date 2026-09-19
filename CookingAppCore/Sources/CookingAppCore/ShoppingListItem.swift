import Foundation
import SwiftData

/// One line on the in-app shopping list — added from a recipe's "Add to Shopping List" button,
/// checked off while actually shopping, and otherwise unrelated to `Recipe` itself: a shopping
/// list item is a snapshot of "I need to buy this," not a live reference back to the recipe (the
/// recipe it came from could be edited or deleted afterward without affecting an already-added
/// item). `sourceRecipeTitle` is kept only for display ("from Shrimp Scampi") — plain text, not a
/// relationship, for the same reason.
@Model
public final class ShoppingListItem {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var amount: String
    public var isChecked: Bool
    public var dateAdded: Date
    public var sourceRecipeTitle: String?

    public init(
        id: UUID = UUID(),
        name: String,
        amount: String,
        isChecked: Bool = false,
        dateAdded: Date = Date(),
        sourceRecipeTitle: String? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.isChecked = isChecked
        self.dateAdded = dateAdded
        self.sourceRecipeTitle = sourceRecipeTitle
    }

    /// The new items `RecipeDetailView`'s "Add to Shopping List" button should insert for
    /// `recipe`, given whatever's already on the list.
    ///
    /// Ingredient amounts are scaled by `scaleFactor` first (see `Ingredient.scaledAmount(by:)`)
    /// so the list reflects whatever serving count was selected when you tapped the button, not
    /// always the recipe's base amount. An ingredient is skipped, not re-added, if the list
    /// already has an *unchecked* item with the same name and amount (case-insensitive on name) —
    /// re-tapping the button on the same recipe at the same scale is idempotent rather than
    /// piling up duplicate rows. Checked-off items don't block a re-add: once you've bought and
    /// checked something off, cooking the recipe again should let you add it back for next time.
    ///
    /// Deliberately doesn't merge quantities across recipes or amount formats ("2 tbsp" from one
    /// recipe and "1/4 cup" of the same ingredient from another stay two separate lines) — real
    /// unit conversion is a much bigger problem than this app's ingredient data model
    /// (`Ingredient.amount` is free text, see its own doc comment) can solve honestly; showing two
    /// lines is accurate, silently guessing a combined total would not be.
    public static func itemsToAdd(for recipe: Recipe, scaleFactor: Double, existingItems: [ShoppingListItem]) -> [ShoppingListItem] {
        let existingUnchecked = Set(
            existingItems
                .filter { !$0.isChecked }
                .map { dedupeKey(name: $0.name, amount: $0.amount) }
        )
        return recipe.ingredients.compactMap { ingredient in
            let scaledAmount = ingredient.scaledAmount(by: scaleFactor)
            guard !existingUnchecked.contains(dedupeKey(name: ingredient.name, amount: scaledAmount)) else {
                return nil
            }
            return ShoppingListItem(name: ingredient.name, amount: scaledAmount, sourceRecipeTitle: recipe.title)
        }
    }

    private static func dedupeKey(name: String, amount: String) -> String {
        "\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(amount)"
    }
}
