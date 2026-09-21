import Foundation
import Testing
@testable import CookingAppCore

@MainActor
struct SessionFlagsTests {

    @Test func acknowledgingPartnerLeftClearsTheFlagSoCookingCanContinue() {
        let peerSync = PeerSyncService(displayName: "me")
        let session = CookingSessionViewModel(recipe: SampleRecipes.pastaForTwo, role: .personB, peerSync: peerSync)

        peerSync.handleReceivedMessage(.leaveSession())
        #expect(session.partnerDidLeave)

        session.acknowledgePartnerLeft()
        #expect(!session.partnerDidLeave)
        session.advance() // still fully usable on their own
        #expect(session.currentIndex == 1)
    }

    @Test func completionIsNotCountedUntilTheViewMarksIt() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        #expect(!session.completionCounted)
    }
}

@MainActor
struct ServingsScalePersistenceTests {

    @Test func snapshotsSavedBeforeScalingExistedStillDecodeAsUnscaled() throws {
        let json = #"{"recipeID":"9E1F0A10-0001-4B7A-9C1A-000000000001","currentIndex":1,"timers":[]}"#
        let snapshot = try JSONDecoder().decode(CookingSessionSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.servingsScaleFactor == nil)
    }

    @Test func aScaledSessionKeepsItsScaleThroughSaveAndRestore() throws {
        let recipe = SampleRecipes.scrambledEggs
        let snapshot = CookingSessionSnapshot(recipeID: recipe.id, role: nil, currentIndex: 0, timers: [], servingsScaleFactor: 2)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CookingSessionSnapshot.self, from: data)
        #expect(decoded.servingsScaleFactor == 2)
    }
}

@MainActor
struct CheckedIngredientsAndMismatchTests {

    @Test func tickedIngredientsSurviveSaveAndRestoreAndOldSnapshotsDecode() throws {
        let snapshot = CookingSessionSnapshot(recipeID: SampleRecipes.scrambledEggs.id, role: nil, currentIndex: 0, timers: [], checkedIngredientNames: ["Eggs", "Butter"])
        let decoded = try JSONDecoder().decode(CookingSessionSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.checkedIngredientNames == ["Eggs", "Butter"])

        let old = #"{"recipeID":"9E1F0A10-0001-4B7A-9C1A-000000000001","currentIndex":1,"timers":[]}"#
        #expect(try JSONDecoder().decode(CookingSessionSnapshot.self, from: Data(old.utf8)).checkedIngredientNames == nil)
    }

    @Test func tickingAnIngredientNotifiesSoItIsPersisted() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        var mutations = 0
        session.onMutated = { mutations += 1 }
        session.setCheckedIngredients(["Eggs"])
        #expect(session.checkedIngredientNames == ["Eggs"])
        #expect(mutations == 1)
    }

    @Test func aJoinerOnADifferentRecipeIsToldInsteadOfWaitingForever() {
        let mine = SampleRecipes.scrambledEggs
        let hosts = SampleRecipes.pastaForTwo
        let peerSync = PeerSyncService(displayName: "me")
        let viewModel = PeerConnectionViewModel(recipe: mine, peerSync: peerSync)
        viewModel.join()

        peerSync.handleReceivedMessage(.recipeSync(recipeID: hosts.id, hostRole: .personA, senderName: "Alex"))

        #expect(viewModel.recipeMismatch)
        #expect(!viewModel.didHandshake)
        viewModel.cancel()
        #expect(!viewModel.recipeMismatch)
    }
}
