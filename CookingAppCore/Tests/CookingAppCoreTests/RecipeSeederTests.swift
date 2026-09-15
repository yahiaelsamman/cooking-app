import Foundation
import SwiftData
import Testing
@testable import CookingAppCore

/// Covers `RecipeSeeder`'s "insert every missing-by-id bundled recipe, touch nothing already
/// present" contract against a real (in-memory) SwiftData `ModelContext`.
///
/// `SampleRecipes.all` are shared, process-wide singleton `@Model` instances — exactly as they
/// are in the real app, which only ever inserts them into one `ModelContext` per launch. Once a
/// SwiftData `@Model` instance has been inserted and saved into a container, inserting that same
/// instance into a *different* container doesn't just risk a race — it silently fails to persist
/// there at all, even when done strictly sequentially (verified empirically while writing this:
/// splitting seeder coverage across multiple fresh in-memory contexts, each seeding for real from
/// `SampleRecipes.all`, produced contexts missing most of what they'd just "successfully" seeded).
/// So the hard rule for this file: at most **one** test in this entire suite may ever call
/// `RecipeSeeder.seedIfNeeded` against the real, unmocked `SampleRecipes.all` — everything that
/// needs to observe seeding behavior does it within that single test's one context, as one
/// continuous narrative, rather than as separate `@Test` functions.
@Suite(.serialized)
struct RecipeSeederTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([Recipe.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func seederFillsGapsLeavesExistingDataAloneAndStaysIdempotent() throws {
        let context = try makeInMemoryContext()

        // --- Phase 1: simulate a device that already ran an older version of the app — it has
        // two of today's bundled recipes (with real user data on one of them, as if actually
        // used) plus a "user's own recipe" standing in for a future add/edit feature. This is
        // deliberately *not* a from-scratch-empty store: that's the scenario that broke on a
        // real device once new bundled recipes/fields shipped after the store already existed.
        //
        // These are freshly-constructed stand-ins that happen to share an id with a real bundled
        // recipe, not the actual `SampleRecipes` singletons — mutating a shared singleton's
        // fields directly here would permanently pollute it for every other test in the process
        // that reads `SampleRecipes.all` afterward, since it's a class (reference type) held in a
        // `static let`.
        let alreadySeeded = Recipe(
            id: SampleRecipes.scrambledEggs.id,
            title: SampleRecipes.scrambledEggs.title,
            summary: SampleRecipes.scrambledEggs.summary,
            soloSteps: SampleRecipes.scrambledEggs.soloSteps,
            iconSystemName: SampleRecipes.scrambledEggs.iconSystemName,
            difficulty: SampleRecipes.scrambledEggs.difficulty,
            soloCookTimeMinutes: SampleRecipes.scrambledEggs.soloCookTimeMinutes,
            ingredients: SampleRecipes.scrambledEggs.ingredients,
            isFavorite: true,
            personalRating: 4,
            personalNotes: "Add more salt next time.",
            timesCooked: 3,
            lastCookedDate: Date(timeIntervalSince1970: 0),
            sortOrder: 0
        )
        let alsoAlreadySeeded = Recipe(
            id: SampleRecipes.searedSteak.id,
            title: SampleRecipes.searedSteak.title,
            summary: SampleRecipes.searedSteak.summary,
            soloSteps: SampleRecipes.searedSteak.soloSteps,
            iconSystemName: SampleRecipes.searedSteak.iconSystemName,
            difficulty: SampleRecipes.searedSteak.difficulty,
            soloCookTimeMinutes: SampleRecipes.searedSteak.soloCookTimeMinutes,
            ingredients: SampleRecipes.searedSteak.ingredients,
            sortOrder: 5
        )

        let custom = Recipe(
            title: "My Own Recipe",
            summary: "Not part of the bundled sample set.",
            soloSteps: [RecipeStep(order: 0, instruction: "Do the one thing.", assignee: .solo, imageSystemName: "star")],
            iconSystemName: "star",
            difficulty: 1,
            soloCookTimeMinutes: 1,
            ingredients: [Ingredient(name: "Thing", amount: "1")],
            sortOrder: 99
        )
        context.insert(alreadySeeded)
        context.insert(alsoAlreadySeeded)
        context.insert(custom)
        try context.save()

        // --- Phase 2: seed. Every bundled recipe not yet present (18 of the 20) should be
        // inserted; the two already there, and the custom one, must be left completely alone.
        RecipeSeeder.seedIfNeeded(context: context)

        let afterFirstSeed = try context.fetch(FetchDescriptor<Recipe>())
        #expect(afterFirstSeed.count == SampleRecipes.all.count + 1, "expected every bundled recipe plus the one custom recipe")

        let stillCustom = afterFirstSeed.first { $0.id == custom.id }
        #expect(stillCustom?.sortOrder == 99, "seeding touched a recipe it never should have inserted or modified")

        let stillFavorited = afterFirstSeed.first { $0.id == alreadySeeded.id }
        #expect(stillFavorited?.isFavorite == true)
        #expect(stillFavorited?.personalRating == 4)
        #expect(stillFavorited?.personalNotes == "Add more salt next time.")
        #expect(stillFavorited?.timesCooked == 3)
        #expect(stillFavorited?.sortOrder == 0, "an already-present recipe's sortOrder must not be reassigned")

        let stillAtFive = afterFirstSeed.first { $0.id == alsoAlreadySeeded.id }
        #expect(stillAtFive?.sortOrder == 5)

        let newlySeeded = afterFirstSeed.filter { $0.id != custom.id && $0.id != alreadySeeded.id && $0.id != alsoAlreadySeeded.id }
        #expect(newlySeeded.count == SampleRecipes.all.count - 2)
        // Appended after the highest sortOrder already in the store (99, the custom recipe's —
        // an intentional consequence of sortOrder being one shared ordering space across every
        // recipe, bundled or not) rather than interleaved anywhere earlier.
        #expect(newlySeeded.allSatisfy { $0.sortOrder > 99 })
        #expect(Set(newlySeeded.map(\.sortOrder)).count == newlySeeded.count, "newly-seeded sortOrders must be unique")

        // --- Phase 3: every bundled recipe is now present — reseeding must be a complete no-op,
        // including not reshuffling any sortOrder that was just assigned.
        let sortOrdersAfterFirstSeed = Dictionary(uniqueKeysWithValues: afterFirstSeed.map { ($0.id, $0.sortOrder) })

        RecipeSeeder.seedIfNeeded(context: context)

        let afterSecondSeed = try context.fetch(FetchDescriptor<Recipe>())
        #expect(afterSecondSeed.count == SampleRecipes.all.count + 1)
        for recipe in afterSecondSeed {
            #expect(recipe.sortOrder == sortOrdersAfterFirstSeed[recipe.id], "\(recipe.title)'s sortOrder changed on a no-op reseed")
        }

        // Exercises `@Query`-style predicate fetching against the seeded store, not just a raw
        // count — the actual access pattern `RecipeListView` uses.
        let title = SampleRecipes.pastaForTwo.title
        var byTitle = FetchDescriptor<Recipe>(predicate: #Predicate { $0.title == title })
        byTitle.fetchLimit = 1
        let byTitleResults = try context.fetch(byTitle)
        #expect(byTitleResults.count == 1)
        #expect(byTitleResults.first?.id == SampleRecipes.pastaForTwo.id)
    }
}
