import SwiftData

/// Populates a fresh (empty) on-device store with the bundled sample recipes on first launch.
/// Safe to call on every launch — it only inserts when the store has zero `Recipe` records, so it
/// never overwrites recipes a future version lets the user add, edit, or delete.
public enum RecipeSeeder {
    public static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Recipe>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        for recipe in SampleRecipes.all {
            context.insert(recipe)
        }
        try? context.save()
    }
}
