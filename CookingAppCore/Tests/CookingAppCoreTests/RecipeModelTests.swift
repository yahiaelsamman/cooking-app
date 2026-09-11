import Testing
@testable import CookingAppCore

struct RecipeModelTests {

    // MARK: - Sample data integrity

    @Test func allSampleRecipesHaveContiguousOrdering() {
        for recipe in SampleRecipes.all {
            let orders = recipe.steps.map(\.order).sorted()
            let expected = Array(0..<recipe.steps.count)
            #expect(orders == expected, "\(recipe.title) steps are not contiguously ordered from 0")
        }
    }

    @Test func allSampleRecipesHaveAtLeastOneStep() {
        for recipe in SampleRecipes.all {
            #expect(!recipe.steps.isEmpty, "\(recipe.title) has no steps")
        }
    }

    @Test func twoPersonRecipesContainBothPersonTracks() {
        for recipe in SampleRecipes.all where recipe.isTwoPerson {
            let hasA = recipe.steps.contains { $0.assignee == .personA }
            let hasB = recipe.steps.contains { $0.assignee == .personB }
            #expect(hasA, "\(recipe.title) is two-person but has no personA steps")
            #expect(hasB, "\(recipe.title) is two-person but has no personB steps")
        }
    }

    @Test func soloRecipesContainOnlySoloSteps() {
        for recipe in SampleRecipes.all where !recipe.isTwoPerson {
            let allSolo = recipe.steps.allSatisfy { $0.assignee == .solo }
            #expect(allSolo, "\(recipe.title) is solo but contains non-solo steps")
        }
    }

    // MARK: - Track filtering

    @Test func soloTrackReturnsFullOrderedStepList() {
        let recipe = SampleRecipes.scrambledEggs
        let track = recipe.track(for: nil)
        #expect(track.count == recipe.steps.count)
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
        let sharedCount = recipe.steps.filter { $0.assignee == .shared }.count

        let trackA = recipe.track(for: .personA)
        let trackB = recipe.track(for: .personB)

        #expect(trackA.filter { $0.assignee == .shared }.count == sharedCount)
        #expect(trackB.filter { $0.assignee == .shared }.count == sharedCount)
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
        let timedStep = recipe.steps.first { $0.timerSeconds == 180 }!

        session.startTimer(for: timedStep)

        #expect(session.runningTimerStepID == timedStep.id)
        #expect(session.timerRemainingSeconds == 180)
        #expect(session.runningTimerStep?.id == timedStep.id)

        session.cancelTimer() // avoid leaking a live Timer past the end of the test
    }

    @Test func cancelTimerClearsRunningState() {
        let recipe = SampleRecipes.searedSteak
        let session = CookingSessionViewModel(recipe: recipe)
        let timedStep = recipe.steps.first { $0.timerSeconds == 180 }!

        session.startTimer(for: timedStep)
        session.cancelTimer()

        #expect(session.runningTimerStepID == nil)
        #expect(session.timerRemainingSeconds == 0)
        #expect(session.runningTimerStep == nil)
    }

    @Test func startTimerOnStepWithoutTimerSecondsDoesNothing() {
        let recipe = SampleRecipes.scrambledEggs
        let session = CookingSessionViewModel(recipe: recipe)
        let untimedStep = recipe.steps.first { $0.timerSeconds == nil }!

        session.startTimer(for: untimedStep)

        #expect(session.runningTimerStepID == nil)
    }

    // MARK: - Recipe metadata regression guards

    @Test func allSampleRecipesHaveValidMetadata() {
        for recipe in SampleRecipes.all {
            #expect((1...3).contains(recipe.difficulty), "\(recipe.title) has an out-of-range difficulty")
            #expect(recipe.cookTimeMinutes > 0, "\(recipe.title) has a non-positive cook time")
            #expect(!recipe.ingredients.isEmpty, "\(recipe.title) has no ingredients")
            #expect(!recipe.iconSystemName.isEmpty, "\(recipe.title) has no icon")
        }
    }

    @Test func allStepsHaveAnImage() {
        for recipe in SampleRecipes.all {
            for step in recipe.steps {
                #expect(!step.imageSystemName.isEmpty, "\(recipe.title) step \(step.order) has no image")
            }
        }
    }

    @Test func atLeastTwoTwoPersonRecipesExist() {
        let twoPersonCount = SampleRecipes.all.filter(\.isTwoPerson).count
        #expect(twoPersonCount >= 2)
    }
}
