import Foundation
import SwiftData
import Testing
@testable import CookingAppCore

/// Covers `RecipeSeeder`'s "only seed an empty store" contract against a real (in-memory)
/// SwiftData `ModelContext` — the whole point of the pass-5 persistence layer per
/// instructions.md, but not previously exercised by any test.
///
/// `SampleRecipes.all` are shared, process-wide singleton `@Model` instances — exactly as they
/// are in the real app, which only ever inserts them into one `ModelContext` per launch. A
/// SwiftData `@Model` instance is bound to whichever context most recently inserted it, so
/// seeding two *different* in-memory contexts from those same singletons within one test process
/// silently steals them from whichever context saw them first. That's a test-isolation hazard,
/// not a production one (a real launch only ever has one `ModelContainer`) — worked around here
/// by driving every assertion that touches the seeded singletons off of one shared context.
struct RecipeSeederTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([Recipe.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func seedingPopulatesAnEmptyStoreCorrectlyAndIsIdempotent() throws {
        let context = try makeInMemoryContext()

        RecipeSeeder.seedIfNeeded(context: context)

        let firstSeedCount = try context.fetchCount(FetchDescriptor<Recipe>())
        #expect(firstSeedCount == SampleRecipes.all.count)

        let fetched = try context.fetch(FetchDescriptor<Recipe>())
        let fetchedByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        for sample in SampleRecipes.all {
            let match = fetchedByID[sample.id]
            #expect(match != nil, "\(sample.title) wasn't seeded under its fixed id")
            #expect(match?.title == sample.title)
            #expect(match?.soloSteps.count == sample.soloSteps.count)
            #expect(match?.supportsTwoPerson == sample.supportsTwoPerson)
        }

        // Exercises `@Query`-style predicate fetching against the seeded store, not just a raw
        // count — the actual access pattern `RecipeListView` uses.
        let title = SampleRecipes.scrambledEggs.title
        var byTitle = FetchDescriptor<Recipe>(predicate: #Predicate { $0.title == title })
        byTitle.fetchLimit = 1
        let byTitleResults = try context.fetch(byTitle)
        #expect(byTitleResults.count == 1)
        #expect(byTitleResults.first?.id == SampleRecipes.scrambledEggs.id)

        // The core safety property: calling it again (as every app launch does) must not
        // duplicate anything.
        RecipeSeeder.seedIfNeeded(context: context)
        RecipeSeeder.seedIfNeeded(context: context)

        let afterReseedCount = try context.fetchCount(FetchDescriptor<Recipe>())
        #expect(afterReseedCount == SampleRecipes.all.count)
    }

    @Test func seedingDoesNotRunWhenTheStoreAlreadyHasAnyRecipeAtAll() throws {
        // Simulates a future "user added/edited their own recipes" state: seeding must back off
        // entirely rather than topping the store back up to the full sample set, since that
        // would silently resurrect a recipe the user deleted. Uses a locally-constructed Recipe
        // (never inserted into any other context), so this test is safe to run alongside the one
        // above with no shared-singleton interference.
        let context = try makeInMemoryContext()
        let custom = Recipe(
            title: "My Own Recipe",
            summary: "Not part of the bundled sample set.",
            soloSteps: [RecipeStep(order: 0, instruction: "Do the one thing.", assignee: .solo, imageSystemName: "star")],
            iconSystemName: "star",
            difficulty: 1,
            soloCookTimeMinutes: 1,
            ingredients: [Ingredient(name: "Thing", amount: "1")]
        )
        context.insert(custom)
        try context.save()

        RecipeSeeder.seedIfNeeded(context: context)

        let fetched = try context.fetch(FetchDescriptor<Recipe>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == custom.id)
    }
}
