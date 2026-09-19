import Foundation
import Testing
@testable import CookingAppCore

struct PreservingStepIDsTests {
    private func step(_ text: String, order: Int, timer: Int? = nil) -> RecipeStep {
        RecipeStep(order: order, instruction: text, assignee: .solo, timerSeconds: timer, imageSystemName: "circle")
    }

    @Test func identicalContentKeepsEveryID() {
        let old = [step("A", order: 0), step("B", order: 1, timer: 60), step("C", order: 2)]
        let new = [step("A", order: 0), step("B", order: 1, timer: 60), step("C", order: 2)]
        let result = Recipe.preservingStepIDs(of: old, in: new)
        #expect(result.map(\.id) == old.map(\.id))
    }

    @Test func insertedStepDoesNotShiftSavedTimerOntoAnotherStep() {
        let old = [step("Boil water", order: 0, timer: 300), step("Drain", order: 1)]
        let new = [step("Salt the water", order: 0), step("Boil water", order: 1, timer: 300), step("Drain", order: 2)]
        let result = Recipe.preservingStepIDs(of: old, in: new)
        #expect(result[1].id == old[0].id)
        #expect(result[2].id == old[1].id)
        #expect(result[0].id != old[0].id && result[0].id != old[1].id)
    }

    @Test func removedStepKeepsLaterIDsByText() {
        let old = [step("A", order: 0), step("B", order: 1, timer: 30), step("C", order: 2)]
        let new = [step("B", order: 0, timer: 30), step("C", order: 1)]
        let result = Recipe.preservingStepIDs(of: old, in: new)
        #expect(result[0].id == old[1].id)
        #expect(result[1].id == old[2].id)
    }

    @Test func reworkedStepKeepsIDOnlyWhenTimerMatches() {
        let old = [step("Bake 10 minutes", order: 0, timer: 600), step("Rest", order: 1)]
        let sameTimer = [step("Bake for 10 min", order: 0, timer: 600), step("Rest", order: 1)]
        #expect(Recipe.preservingStepIDs(of: old, in: sameTimer)[0].id == old[0].id)
        let newTimer = [step("Bake 12 minutes", order: 0, timer: 720), step("Rest", order: 1)]
        #expect(Recipe.preservingStepIDs(of: old, in: newTimer)[0].id != old[0].id)
    }

    @Test func duplicateInstructionsMapOneToOne() {
        let old = [step("Stir", order: 0), step("Stir", order: 1)]
        let new = [step("Stir", order: 0), step("Stir", order: 1), step("Stir", order: 2)]
        let ids = Recipe.preservingStepIDs(of: old, in: new).map(\.id)
        #expect(Set(ids).count == 3)
        #expect(ids[0] == old[0].id && ids[1] == old[1].id)
    }
}
