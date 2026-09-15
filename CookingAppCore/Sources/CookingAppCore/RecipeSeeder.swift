import SwiftData

/// Inserts every bundled sample recipe the on-device store doesn't already have (matched by its
/// fixed id) — safe to call on every launch. A recipe already present is left completely
/// untouched, including every user field on it (`isFavorite`, `personalRating`, `personalNotes`,
/// `timesCooked`, `lastCookedDate`, `sortOrder`) — reseeding never resets a rating or a favorite,
/// and never re-syncs a bundled recipe's curated content over a user's own data about it.
///
/// This is deliberately more permissive than an earlier version, which backed off entirely the
/// moment the store had *any* recipe in it at all. That guard meant a device that had ever run the
/// app before could never receive a bundled recipe added in a later version — including new
/// `heroImageName`s on the original 8 once photos shipped — without a full uninstall/reinstall to
/// wipe the store. That's a real bug hit in practice, not a hypothetical: a real device kept
/// showing the old photo-less recipes after a build that added photos, until reinstalled.
///
/// The tradeoff, carried forward from the old design's stated purpose: if a future version adds
/// real recipe *deletion*, a bundled recipe the user deleted would come back on the next launch,
/// since nothing here distinguishes "never seeded" from "seeded, then deleted." There's no
/// delete UI yet, so this can't actually happen today — but whichever pass adds deletion needs a
/// tombstone (e.g. a stored set of deleted bundled ids) alongside it, or this needs to change.
public enum RecipeSeeder {
    public static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        let existingIDs = Set(existing.map(\.id))
        let missing = SampleRecipes.all.filter { !existingIDs.contains($0.id) }
        guard !missing.isEmpty else { return }

        // New bundled recipes are appended to the end of the user's manual "My Order" ordering,
        // never interleaved into it.
        var nextSortOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        for recipe in missing {
            recipe.sortOrder = nextSortOrder
            nextSortOrder += 1
            context.insert(recipe)
        }
        try? context.save()
    }
}
