import Foundation
import Testing
@testable import CookingAppCore

struct RecipeModelTests {

    // MARK: - Sample data integrity

    @Test func allSoloStepListsAreContiguouslyOrdered() {
        for recipe in SampleRecipes.all {
            let orders = recipe.soloSteps.map(\.order).sorted()
            let expected = Array(0..<recipe.soloSteps.count)
            #expect(orders == expected, "\(recipe.title) solo steps are not contiguously ordered from 0")
        }
    }

    @Test func allTwoPersonStepListsAreContiguouslyOrdered() {
        for recipe in SampleRecipes.all {
            guard let twoPersonSteps = recipe.twoPersonSteps else { continue }
            let orders = twoPersonSteps.map(\.order).sorted()
            let expected = Array(0..<twoPersonSteps.count)
            #expect(orders == expected, "\(recipe.title) two-person steps are not contiguously ordered from 0")
        }
    }

    @Test func allSampleRecipesHaveAtLeastOneSoloStep() {
        for recipe in SampleRecipes.all {
            #expect(!recipe.soloSteps.isEmpty, "\(recipe.title) has no solo steps")
        }
    }

    @Test func twoPersonRecipesContainBothPersonTracks() {
        for recipe in SampleRecipes.all {
            guard let twoPersonSteps = recipe.twoPersonSteps else { continue }
            let hasA = twoPersonSteps.contains { $0.assignee == .personA }
            let hasB = twoPersonSteps.contains { $0.assignee == .personB }
            #expect(hasA, "\(recipe.title) has two-person steps but no personA steps")
            #expect(hasB, "\(recipe.title) has two-person steps but no personB steps")
        }
    }

    @Test func soloStepsAreAlwaysTaggedSolo() {
        for recipe in SampleRecipes.all {
            let allSolo = recipe.soloSteps.allSatisfy { $0.assignee == .solo }
            #expect(allSolo, "\(recipe.title)'s solo steps contain a non-.solo assignee")
        }
    }

    @Test func soloStepInstructionsNeverSayBoth() {
        // The whole point of authoring a separate solo version rather than deriving one from the
        // two-person split: it should read naturally for one person, not carry "Both:" phrasing
        // left over from the shared two-person steps.
        for recipe in SampleRecipes.all {
            for step in recipe.soloSteps {
                #expect(!step.instruction.hasPrefix("Both:"), "\(recipe.title) solo step reads like a two-person shared step: \(step.instruction)")
            }
        }
    }

    // MARK: - Track filtering

    @Test func soloTrackReturnsFullOrderedSoloStepList() {
        let recipe = SampleRecipes.scrambledEggs
        let track = recipe.track(for: nil)
        #expect(track.count == recipe.soloSteps.count)
        #expect(track.map(\.order) == track.map(\.order).sorted())
    }

    @Test func personATrackIncludesSharedAndPersonASteps() {
        let recipe = SampleRecipes.pastaForTwo
        let track = recipe.track(for: .personA)

        #expect(!track.isEmpty)
        #expect(track.allSatisfy { $0.assignee == .personA || $0.assignee == .shared })
        #expect(!track.contains { $0.assignee == .personB })
        // ordering preserved
        #expect(track.map(\.order) == track.map(\.order).sorted())
    }

    @Test func personBTrackIncludesSharedAndPersonBSteps() {
        let recipe = SampleRecipes.pastaForTwo
        let track = recipe.track(for: .personB)

        #expect(!track.isEmpty)
        #expect(track.allSatisfy { $0.assignee == .personB || $0.assignee == .shared })
        #expect(!track.contains { $0.assignee == .personA })
        #expect(track.map(\.order) == track.map(\.order).sorted())
    }

    @Test func personAAndPersonBTracksBothContainSharedSteps() {
        let recipe = SampleRecipes.pastaForTwo
        let sharedCount = recipe.twoPersonSteps!.filter { $0.assignee == .shared }.count

        let trackA = recipe.track(for: .personA)
        let trackB = recipe.track(for: .personB)

        #expect(trackA.filter { $0.assignee == .shared }.count == sharedCount)
        #expect(trackB.filter { $0.assignee == .shared }.count == sharedCount)
    }

    // MARK: - supportsTwoPerson

    @Test func recipesWithTwoPersonStepsReportSupportsTwoPerson() {
        for recipe in SampleRecipes.all where recipe.twoPersonSteps != nil {
            #expect(recipe.supportsTwoPerson)
        }
    }

    @Test func soloOnlyRecipesReportNoTwoPersonSupport() {
        for recipe in SampleRecipes.all where recipe.twoPersonSteps == nil {
            #expect(!recipe.supportsTwoPerson)
        }
    }

    @Test func atLeastTwoRecipesSupportTwoPerson() {
        let count = SampleRecipes.all.filter(\.supportsTwoPerson).count
        #expect(count >= 2)
    }

    @Test func trackForRoleFallsBackToSoloStepsWhenRecipeHasNoTwoPersonSteps() {
        // Defensive fallback only — the UI never actually requests a role on a recipe that
        // doesn't support two-person mode, since the toggle isn't offered for it at all.
        let recipe = SampleRecipes.scrambledEggs
        #expect(!recipe.supportsTwoPerson)

        let track = recipe.track(for: .personA)
        #expect(track.map(\.id) == recipe.soloSteps.sorted { $0.order < $1.order }.map(\.id))
    }

    @Test func trackForRoleFallsBackToSoloStepsForPersonBToo() {
        // Same fallback, other role — regression guard against a fix that only handled personA.
        let recipe = SampleRecipes.scrambledEggs
        let track = recipe.track(for: .personB)
        #expect(track.map(\.id) == recipe.soloSteps.sorted { $0.order < $1.order }.map(\.id))
    }

    @Test func trackForNilRoleAlwaysReturnsSoloStepsEvenWhenTwoPersonStepsExist() {
        // `role: nil` means solo mode — must never accidentally read from `twoPersonSteps`, even
        // for a recipe that has a two-person split.
        let recipe = SampleRecipes.pastaForTwo
        let track = recipe.track(for: nil)
        #expect(track.map(\.id) == recipe.soloSteps.sorted { $0.order < $1.order }.map(\.id))
        #expect(track.allSatisfy { $0.assignee == .solo })
    }

    // MARK: - Cook time by mode

    @Test func cookTimeForSoloModeIsAlwaysTheSoloValue() {
        for recipe in SampleRecipes.all {
            #expect(recipe.cookTimeMinutes(forTwoPerson: false) == recipe.soloCookTimeMinutes)
        }
    }

    @Test func cookTimeForTwoPersonModeUsesTheTwoPersonValueWhenPresent() {
        let recipe = SampleRecipes.pastaForTwo
        #expect(recipe.twoPersonCookTimeMinutes != nil)
        #expect(recipe.cookTimeMinutes(forTwoPerson: true) == recipe.twoPersonCookTimeMinutes)
    }

    @Test func twoPersonCookTimeIsShorterThanSoloForRecipesWithACuratedSplit() {
        // Splitting labor should actually save time — a regression guard against accidentally
        // authoring a two-person time that isn't actually faster than cooking it alone.
        for recipe in SampleRecipes.all where recipe.supportsTwoPerson {
            #expect(recipe.cookTimeMinutes(forTwoPerson: true) < recipe.cookTimeMinutes(forTwoPerson: false), "\(recipe.title)'s two-person time isn't faster than solo")
        }
    }

    @Test func cookTimeForTwoPersonModeFallsBackToSoloValueWhenRecipeHasNoTwoPersonSteps() {
        let recipe = SampleRecipes.scrambledEggs
        #expect(recipe.cookTimeMinutes(forTwoPerson: true) == recipe.soloCookTimeMinutes)
    }

    // MARK: - CookingSessionViewModel (pure logic, no live networking)

    @Test func sessionStartsAtFirstStepAndIsNotComplete() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        #expect(session.currentIndex == 0)
        #expect(session.currentStep?.order == 0)
        #expect(!session.isComplete)
    }

    @Test func advanceMovesThroughEveryStepThenCompletes() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        let stepCount = session.track.count

        for _ in 0..<stepCount {
            #expect(!session.isComplete)
            session.advance()
        }

        #expect(session.isComplete)
        #expect(session.currentStep == nil)
    }

    @Test func advanceStopsAtEndAndDoesNotOvershoot() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        let stepCount = session.track.count

        for _ in 0..<(stepCount + 5) {
            session.advance()
        }

        #expect(session.currentIndex == stepCount)
        #expect(session.isComplete)
    }

    @Test func goBackStopsAtZeroAndDoesNotGoNegative() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)

        for _ in 0..<5 {
            session.goBack()
        }

        #expect(session.currentIndex == 0)
        #expect(!session.isComplete)
    }

    @Test func advanceThenGoBackReturnsToPreviousStep() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        session.advance()
        session.advance()
        #expect(session.currentIndex == 2)

        session.goBack()
        #expect(session.currentIndex == 1)
        #expect(session.currentStep?.order == 1)
    }

    @Test func singleStepRecipeIsLastStepImmediatelyAndCompletesOnOneAdvance() {
        // Edge case for the "divide by track.count" math in progressFraction/isLastStep: a
        // one-step track means step 0 is simultaneously the first AND last step.
        let recipe = Recipe(
            title: "One-Step Recipe",
            summary: "Just microwave it.",
            soloSteps: [RecipeStep(order: 0, instruction: "Microwave for 1 minute.", assignee: .solo, imageSystemName: "timer")],
            iconSystemName: "timer",
            difficulty: 1,
            soloCookTimeMinutes: 1,
            ingredients: [Ingredient(name: "Leftovers", amount: "1 portion")]
        )
        let session = CookingSessionViewModel(recipe: recipe)

        #expect(session.isLastStep)
        #expect(session.progressFraction == 0)
        #expect(!session.isComplete)

        session.advance()

        #expect(session.isComplete)
        #expect(session.progressFraction == 1.0)
        #expect(session.currentStep == nil)
    }

    @Test func progressTextReflectsFilteredTrackLength() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.pastaForTwo, role: .personA)
        let expectedTotal = SampleRecipes.pastaForTwo.track(for: .personA).count

        #expect(session.progressText == "Step 1 of \(expectedTotal)")
        session.advance()
        #expect(session.progressText == "Step 2 of \(expectedTotal)")
    }

    @Test func personATrackDoesNotAdvanceThroughPersonBSteps() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.pastaForTwo, role: .personA)
        #expect(session.track.allSatisfy { $0.assignee == .personA || $0.assignee == .shared })
    }

    // MARK: - Timer (deterministic state only — see note below)

    // Foundation's `Timer` needs an actively-spinning RunLoop to fire, which the app provides
    // (the main run loop) but a `swift test` process's threading model doesn't reliably
    // guarantee. So these test the public state transitions `startTimer`/`cancelTimer` make
    // synchronously, not the real 1-second-interval countdown firing to completion — that's
    // covered by manual verification in the running app instead (see instructions.md).

    @Test func startTimerSetsRunningStateForTimedStep() {
        let recipe = SampleRecipes.searedSteak
        let session = CookingSessionViewModel(recipe: recipe)
        let timedStep = recipe.soloSteps.first { $0.timerSeconds == 180 }!

        session.startTimer(for: timedStep)

        #expect(session.activeTimer(for: timedStep)?.remainingSeconds == 180)
        #expect(session.activeTimer(for: timedStep)?.totalSeconds == 180)

        session.cancelTimer(for: timedStep) // avoid leaking a live Timer past the end of the test
    }

    @Test func cancelTimerClearsRunningState() {
        let recipe = SampleRecipes.searedSteak
        let session = CookingSessionViewModel(recipe: recipe)
        let timedStep = recipe.soloSteps.first { $0.timerSeconds == 180 }!

        session.startTimer(for: timedStep)
        session.cancelTimer(for: timedStep)

        #expect(session.activeTimer(for: timedStep) == nil)
        #expect(session.activeTimers.isEmpty)
    }

    @Test func startTimerOnStepWithoutTimerSecondsDoesNothing() {
        let recipe = SampleRecipes.scrambledEggs
        let session = CookingSessionViewModel(recipe: recipe)
        let untimedStep = recipe.soloSteps.first { $0.timerSeconds == nil }!

        session.startTimer(for: untimedStep)

        #expect(session.activeTimer(for: untimedStep) == nil)
        #expect(session.activeTimers.isEmpty)
    }

    @Test func timersStackAcrossMultipleSteps() {
        let recipe = SampleRecipes.pastaForTwo
        let session = CookingSessionViewModel(recipe: recipe, role: .personA)
        let sauceStep = recipe.twoPersonSteps!.first { $0.timerSeconds == 600 && $0.assignee == .personA }!
        let otherTimedStep = recipe.twoPersonSteps!.first { $0.assignee == .personB && $0.timerSeconds != nil }!

        session.startTimer(for: sauceStep)
        session.startTimer(for: otherTimedStep)

        #expect(session.activeTimers.count == 2)
        #expect(session.activeTimer(for: sauceStep) != nil)
        #expect(session.activeTimer(for: otherTimedStep) != nil)

        session.cancelTimer(for: sauceStep)

        #expect(session.activeTimers.count == 1)
        #expect(session.activeTimer(for: sauceStep) == nil)
        #expect(session.activeTimer(for: otherTimedStep) != nil)

        session.cancelTimer(for: otherTimedStep)
        #expect(session.activeTimers.isEmpty)
    }

    @Test func restartingATimerOnTheSameStepReplacesItRatherThanStacking() {
        let recipe = SampleRecipes.searedSteak
        let session = CookingSessionViewModel(recipe: recipe)
        let timedStep = recipe.soloSteps.first { $0.timerSeconds == 180 }!

        session.startTimer(for: timedStep)
        session.startTimer(for: timedStep)

        #expect(session.activeTimers.count == 1)
        session.cancelTimer(for: timedStep)
    }

    // MARK: - Recipe metadata regression guards

    @Test func allSampleRecipeIDsAreUnique() {
        // Fixed UUID literals, not random `UUID()` (see instructions.md's pitfalls) — a copy/paste
        // duplicate here would silently break the host/joiner recipeID handshake for whichever
        // two recipes collided.
        let ids = SampleRecipes.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate recipe id found among SampleRecipes.all")
    }

    @Test func allStepIDsAreUniqueWithinEachRecipesStepList() {
        for recipe in SampleRecipes.all {
            let soloIDs = recipe.soloSteps.map(\.id)
            #expect(Set(soloIDs).count == soloIDs.count, "\(recipe.title) has duplicate solo step ids")

            if let twoPersonSteps = recipe.twoPersonSteps {
                let twoPersonIDs = twoPersonSteps.map(\.id)
                #expect(Set(twoPersonIDs).count == twoPersonIDs.count, "\(recipe.title) has duplicate two-person step ids")
            }
        }
    }

    @Test func twoPersonCookTimeIsNilExactlyWhenTwoPersonStepsAreNil() {
        // Regression guard on the invariant `cookTimeMinutes(forTwoPerson:)`'s fallback relies on:
        // the two fields should never disagree about whether this recipe supports two-person mode.
        for recipe in SampleRecipes.all {
            #expect((recipe.twoPersonCookTimeMinutes != nil) == (recipe.twoPersonSteps != nil), "\(recipe.title) has mismatched twoPersonCookTimeMinutes/twoPersonSteps nil-ness")
        }
    }

    @Test func allSampleRecipesHaveValidMetadata() {
        for recipe in SampleRecipes.all {
            #expect((1...3).contains(recipe.difficulty), "\(recipe.title) has an out-of-range difficulty")
            #expect((0...3).contains(recipe.spiceLevel), "\(recipe.title) has an out-of-range spice level")
            #expect(recipe.soloCookTimeMinutes > 0, "\(recipe.title) has a non-positive solo cook time")
            if let twoPersonCookTimeMinutes = recipe.twoPersonCookTimeMinutes {
                #expect(twoPersonCookTimeMinutes > 0, "\(recipe.title) has a non-positive two-person cook time")
            }
            #expect(!recipe.ingredients.isEmpty, "\(recipe.title) has no ingredients")
            #expect(!recipe.iconSystemName.isEmpty, "\(recipe.title) has no icon")
        }
    }

    @Test func heroImageNameWhenPresentIsNonEmpty() {
        // heroImageName is nil-by-default (no placeholder empty-string convention) — this only
        // guards against an accidentally-empty string once recipes start getting real photos.
        for recipe in SampleRecipes.all {
            if let heroImageName = recipe.heroImageName {
                #expect(!heroImageName.isEmpty, "\(recipe.title) has an empty heroImageName")
            }
        }
    }

    @Test func everyBundledRecipeStartsWithNoUserData() {
        // User data (favorite/rating/notes/cook history/manual order) belongs entirely to the
        // person using the app — a regression guard against ever accidentally hardcoding fake
        // user data into the bundled content itself. RecipeSeeder relies on every bundled
        // recipe's sortOrder starting at its init default (0) too, since it overwrites sortOrder
        // itself at seed time based on array position — see RecipeSeederTests.
        for recipe in SampleRecipes.all {
            #expect(!recipe.isFavorite, "\(recipe.title) is hardcoded as a favorite")
            #expect(recipe.personalRating == nil, "\(recipe.title) has a hardcoded personal rating")
            #expect(recipe.personalNotes.isEmpty, "\(recipe.title) has hardcoded personal notes")
            #expect(recipe.timesCooked == 0, "\(recipe.title) has a hardcoded cook count")
            #expect(recipe.lastCookedDate == nil, "\(recipe.title) has a hardcoded last-cooked date")
            #expect(!recipe.isUserCreated, "\(recipe.title) is marked user-created but is part of the bundle")
        }
    }

    @Test func allSampleRecipeTitlesAreUnique() {
        // Titles aren't used for identity anywhere load-bearing (ids are), but a duplicate title
        // would be confusing in the recipe list and is almost certainly a copy/paste mistake.
        let titles = SampleRecipes.all.map(\.title)
        #expect(Set(titles).count == titles.count, "duplicate recipe title found among SampleRecipes.all")
    }

    @Test func atLeastTwentySampleRecipesExist() {
        #expect(SampleRecipes.all.count >= 20)
    }

    // MARK: - Recipe.nextSortOrder(after:)

    @Test func nextSortOrderIsZeroForAnEmptyList() {
        #expect(Recipe.nextSortOrder(after: []) == 0)
    }

    @Test func nextSortOrderIsOneMoreThanTheCurrentMax() {
        let recipes = [
            makeMinimalRecipe(sortOrder: 3),
            makeMinimalRecipe(sortOrder: 7),
            makeMinimalRecipe(sortOrder: 1)
        ]
        #expect(Recipe.nextSortOrder(after: recipes) == 8)
    }

    private func makeMinimalRecipe(sortOrder: Int) -> Recipe {
        Recipe(
            title: "Test",
            summary: "Test",
            soloSteps: [RecipeStep(order: 0, instruction: "Do it.", assignee: .solo, imageSystemName: "star")],
            iconSystemName: "star",
            difficulty: 1,
            soloCookTimeMinutes: 1,
            ingredients: [Ingredient(name: "Thing", amount: "1")],
            sortOrder: sortOrder
        )
    }

    @Test func allStepsHaveAnImage() {
        for recipe in SampleRecipes.all {
            for step in recipe.soloSteps {
                #expect(!step.imageSystemName.isEmpty, "\(recipe.title) solo step \(step.order) has no image")
            }
            for step in recipe.twoPersonSteps ?? [] {
                #expect(!step.imageSystemName.isEmpty, "\(recipe.title) two-person step \(step.order) has no image")
            }
        }
    }

    // MARK: - Codable round-trips (RecipeStep/Ingredient aren't SwiftData relationships — see
    // Recipe.swift's doc comment — so their own Codable conformance is what actually persists them)

    @Test func recipeStepRoundTripsThroughJSONIncludingANilTimer() throws {
        let step = RecipeStep(order: 2, instruction: "Whisk it.", assignee: .shared, timerSeconds: nil, imageSystemName: "sparkles")

        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(RecipeStep.self, from: data)

        #expect(decoded == step)
        #expect(decoded.timerSeconds == nil)
    }

    @Test func recipeStepRoundTripsThroughJSONWithATimer() throws {
        let step = RecipeStep(order: 4, instruction: "Sear it.", assignee: .personA, timerSeconds: 180, imageSystemName: "timer")

        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(RecipeStep.self, from: data)

        #expect(decoded == step)
        #expect(decoded.timerSeconds == 180)
    }

    @Test func ingredientRoundTripsThroughJSON() throws {
        let ingredient = Ingredient(name: "Salt", amount: "A pinch")

        let data = try JSONEncoder().encode(ingredient)
        let decoded = try JSONDecoder().decode(Ingredient.self, from: data)

        #expect(decoded == ingredient)
    }

    @Test func allDietaryTagsHaveANonEmptyLabelAndSystemImage() {
        for tag in DietaryTag.allCases {
            #expect(!tag.label.isEmpty)
            #expect(!tag.systemImage.isEmpty)
        }
    }
}
