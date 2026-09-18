import SwiftData

/// Inserts every bundled sample recipe the on-device store doesn't already have (matched by its
/// fixed id), and refreshes every already-seeded bundled recipe's *curated* content (steps,
/// images, ingredients, ...) to match the current `SampleRecipes.swift` — safe to call on every
/// launch. A recipe's user fields (`isFavorite`, `personalRating`, `personalNotes`,
/// `timesCooked`, `lastCookedDate`, `sortOrder`) are never touched either way — reseeding never
/// resets a rating or a favorite. A user-created recipe (`isUserCreated`) is never touched at all,
/// missing or not — it has no bundled counterpart to sync from.
///
/// This is deliberately more permissive than an earlier version, which backed off entirely the
/// moment the store had *any* recipe in it at all. That guard meant a device that had ever run the
/// app before could never receive a bundled recipe added in a later version — including new
/// `heroImageName`s on the original 8 once photos shipped — without a full uninstall/reinstall to
/// wipe the store. That's a real bug hit in practice, not a hypothetical: a real device kept
/// showing the old photo-less recipes after a build that added photos, until reinstalled.
///
/// A later version fixed that for *missing* recipes but not for already-seeded ones with *changed*
/// content — an already-seeded recipe was still left completely alone, so a step's new
/// `stepImageName` (or any other curated-field edit) on a recipe seeded before that field existed
/// would never reach the device either, again short of a reinstall. `updateBundledContent(from:)`
/// closes that gap by re-syncing curated fields on every launch instead of only inserting once.
///
/// The tradeoff, carried forward from the old design's stated purpose: if a future version adds
/// real recipe *deletion*, a bundled recipe the user deleted would come back on the next launch,
/// since nothing here distinguishes "never seeded" from "seeded, then deleted." There's no
/// delete UI yet, so this can't actually happen today — but whichever pass adds deletion needs a
/// tombstone (e.g. a stored set of deleted bundled ids) alongside it, or this needs to change.
public enum RecipeSeeder {
    public static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        var nextSortOrder = Recipe.nextSortOrder(after: existing)
        for recipe in SampleRecipes.all {
            if let existingRecipe = existingByID[recipe.id] {
                guard !existingRecipe.isUserCreated else { continue }
                existingRecipe.updateBundledContent(from: recipe)
            } else {
                // New bundled recipes are appended to the end of the user's manual "My Order"
                // ordering, never interleaved into it.
                recipe.sortOrder = nextSortOrder
                nextSortOrder += 1
                context.insert(recipe)
            }
        }
        try? context.save()
    }
}
