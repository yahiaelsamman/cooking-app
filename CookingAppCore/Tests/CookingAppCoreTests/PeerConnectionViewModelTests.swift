import Foundation
import MultipeerConnectivity
import Testing
@testable import CookingAppCore

/// Covers the host/join connection-screen logic in `PeerConnectionViewModel` — previously
/// untested. Drives a real `PeerSyncService` through its synchronous internal handlers (same
/// approach as `PeerSyncServiceTests`/`CookingSessionViewModelTests`) rather than real networking.
///
/// `@MainActor`: `PeerConnectionViewModel`/`PeerSyncService` are both `@MainActor` now (see their
/// doc comments), so this suite runs on the main actor too — every call below is a plain
/// synchronous call to a main-actor-isolated method, exactly as production code makes it.
///
/// `didHandshake`'s "joiner accepted a matching recipeSync" path used to assign on its own
/// `DispatchQueue.main.async`, redundant on top of the hop `PeerSyncService`'s own delegate
/// methods already did — which meant it wasn't reliably observable from a `swift test` process
/// with no actively-spinning main run loop, same limitation this codebase's Timer-based
/// countdowns have. Now that both types are provably `@MainActor`, that redundant inner dispatch
/// is gone, so `joinerHandshakeSucceedsOnAMatchingRecipeSync` below exercises the real path
/// directly, alongside the guard conditions that gate it (wrong role, mismatched recipe id).
@MainActor
struct PeerConnectionViewModelTests {

    private func makeViewModel(recipe: Recipe = SampleRecipes.scrambledEggs) -> PeerConnectionViewModel {
        PeerConnectionViewModel(recipe: recipe, peerSync: PeerSyncService(displayName: "test-device"))
    }

    @Test func hostSetsHostRoleAndBeginsAdvertising() {
        let viewModel = makeViewModel()

        viewModel.host(as: .personA)

        #expect(viewModel.role == .host)
        #expect(viewModel.connectionState == .advertising)
    }

    @Test func hostResolvesItsOwnChosenRoleImmediately() {
        // The host doesn't wait on any message for this — it knows its own choice right away.
        let viewModel = makeViewModel()

        viewModel.host(as: .personB)

        #expect(viewModel.resolvedStepAssignee == .personB)
    }

    @Test func joinerResolvesTheOppositeOfWhateverTheHostChose() {
        let recipe = SampleRecipes.scrambledEggs
        let peerSync = PeerSyncService(displayName: "me")
        let viewModel = PeerConnectionViewModel(recipe: recipe, peerSync: peerSync)
        viewModel.join()

        peerSync.handleReceivedMessage(.recipeSync(recipeID: recipe.id, hostRole: .personB, senderName: "Alex"))

        #expect(viewModel.resolvedStepAssignee == .personA)
    }

    @Test func partnerNameReflectsThePeerSyncServices() {
        let recipe = SampleRecipes.scrambledEggs
        let peerSync = PeerSyncService(displayName: "me")
        let viewModel = PeerConnectionViewModel(recipe: recipe, peerSync: peerSync)
        viewModel.join()
        #expect(viewModel.partnerName == nil)

        peerSync.handleReceivedMessage(.recipeSync(recipeID: recipe.id, hostRole: .personA, senderName: "Alex"))

        #expect(viewModel.partnerName == "Alex")
    }

    @Test func joinSetsJoinerRoleAndBeginsBrowsing() {
        let viewModel = makeViewModel()

        viewModel.join()

        #expect(viewModel.role == .joiner)
        #expect(viewModel.connectionState == .browsing)
    }

    @Test func cancelTearsDownTheUnderlyingConnection() {
        let viewModel = makeViewModel()
        viewModel.host(as: .personA)
        #expect(viewModel.connectionState == .advertising)

        viewModel.cancel()

        #expect(viewModel.connectionState == .idle)
    }

    // MARK: - hostDidConnect (synchronous — no dispatch involved)

    @Test func hostDidConnectSetsDidHandshakeWhenHosting() {
        let viewModel = makeViewModel()
        viewModel.host(as: .personA)
        #expect(!viewModel.didHandshake)

        viewModel.hostDidConnect()

        #expect(viewModel.didHandshake)
    }

    @Test func hostDidConnectDoesNothingBeforeHostIsCalled() {
        // Guards against a stray/late callback firing before `host()` has even set `role`.
        let viewModel = makeViewModel()

        viewModel.hostDidConnect()

        #expect(!viewModel.didHandshake)
    }

    @Test func hostDidConnectDoesNothingForAJoiner() {
        // The joiner's handshake signal is the incoming `recipeSync` message, not this method —
        // it should be a no-op if role is `.joiner`.
        let viewModel = makeViewModel()
        viewModel.join()

        viewModel.hostDidConnect()

        #expect(!viewModel.didHandshake)
    }

    @Test func hostDidConnectIsIdempotentOnceAlreadyHandshaken() {
        let viewModel = makeViewModel()
        viewModel.host(as: .personA)
        viewModel.hostDidConnect()
        #expect(viewModel.didHandshake)

        viewModel.hostDidConnect() // a later reconnect during an already-active cook session

        #expect(viewModel.didHandshake) // still true, no crash/misbehavior
    }

    // MARK: - onRecipeSync guard conditions (synchronous early-return paths)

    @Test func recipeSyncMessageIsIgnoredBeforeJoinIsCalled() {
        // role is nil until `join()` runs — a stray recipeSync arriving before that shouldn't be
        // able to flip didHandshake.
        let recipe = SampleRecipes.scrambledEggs
        let peerSync = PeerSyncService(displayName: "me")
        let viewModel = PeerConnectionViewModel(recipe: recipe, peerSync: peerSync)

        peerSync.handleReceivedMessage(.recipeSync(recipeID: recipe.id, hostRole: .personA, senderName: "Alex"))

        #expect(!viewModel.didHandshake)
    }

    @Test func recipeSyncMessageForADifferentRecipeIsIgnored() {
        let recipe = SampleRecipes.scrambledEggs
        let peerSync = PeerSyncService(displayName: "me")
        let viewModel = PeerConnectionViewModel(recipe: recipe, peerSync: peerSync)
        viewModel.join()

        peerSync.handleReceivedMessage(.recipeSync(recipeID: SampleRecipes.searedSteak.id, hostRole: .personA, senderName: "Alex"))

        #expect(!viewModel.didHandshake)
    }

    @Test func recipeSyncMessageIsIgnoredWhileHosting() {
        // The host is the one who *sends* recipeSync, not the one who waits on it — its own
        // handshake path is `hostDidConnect()`, so an incoming recipeSync (which shouldn't
        // normally happen while hosting) must not be able to set didHandshake either.
        let recipe = SampleRecipes.scrambledEggs
        let peerSync = PeerSyncService(displayName: "me")
        let viewModel = PeerConnectionViewModel(recipe: recipe, peerSync: peerSync)
        viewModel.host(as: .personA)

        peerSync.handleReceivedMessage(.recipeSync(recipeID: recipe.id, hostRole: .personB, senderName: "Alex"))

        #expect(!viewModel.didHandshake)
    }

    // MARK: - onRecipeSync success path (previously untestable — see the file's doc comment)

    @Test func joinerHandshakeSucceedsOnAMatchingRecipeSync() {
        let recipe = SampleRecipes.scrambledEggs
        let peerSync = PeerSyncService(displayName: "me")
        let viewModel = PeerConnectionViewModel(recipe: recipe, peerSync: peerSync)
        viewModel.join()
        #expect(!viewModel.didHandshake)

        peerSync.handleReceivedMessage(.recipeSync(recipeID: recipe.id, hostRole: .personA, senderName: "Alex"))

        #expect(viewModel.didHandshake)
        #expect(viewModel.resolvedStepAssignee == .personB)
    }

    // MARK: - discoveredPeers / connectionState pass-through

    @Test func discoveredPeersReflectsThePeerSyncServices() {
        let peerSync = PeerSyncService(displayName: "me")
        let viewModel = PeerConnectionViewModel(recipe: SampleRecipes.scrambledEggs, peerSync: peerSync)
        viewModel.join()

        peerSync.handleFoundPeer(MCPeerID(displayName: "partner-device"))

        #expect(viewModel.discoveredPeers.count == 1)
        #expect(viewModel.discoveredPeers.first?.displayName == "partner-device")
    }

    @Test func connectInvitesThePeerThroughPeerSync() {
        let peerSync = PeerSyncService(displayName: "me")
        let viewModel = PeerConnectionViewModel(recipe: SampleRecipes.scrambledEggs, peerSync: peerSync)
        viewModel.join()
        let peer = MCPeerID(displayName: "partner-device")

        viewModel.connect(to: peer)

        #expect(viewModel.connectionState == .connecting)
    }
}
