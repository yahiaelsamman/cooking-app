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
}
