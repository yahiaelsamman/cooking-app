import Foundation
import MultipeerConnectivity
import Testing
@testable import CookingAppCore

/// Covers the host/join connection-screen logic in `PeerConnectionViewModel` — previously
/// untested. Drives a real `PeerSyncService` through its synchronous internal handlers (same
/// approach as `PeerSyncServiceTests`/`CookingSessionViewModelTests`) rather than real networking.
///
/// `didHandshake`'s "joiner accepted a matching recipeSync" path assigns on
/// `DispatchQueue.main.async` (see `PeerConnectionViewModel.init`), which — like this codebase's
/// Timer-based countdowns — isn't reliably observable from a `swift test` process with no
/// actively-spinning main run loop. So this file only asserts the synchronous *guard* conditions
/// that gate that assignment (wrong role, mismatched recipe id): both are directly observable
/// without waiting on anything async. The one *synchronous* handshake path — `hostDidConnect()`,
/// which assigns `didHandshake` directly with no dispatch — is fully covered below.
struct PeerConnectionViewModelTests {

    @Test func hostSetsHostRoleAndBeginsAdvertising() {
        let viewModel = PeerConnectionViewModel(recipe: SampleRecipes.scrambledEggs)

        viewModel.host(as: .personA)

        #expect(viewModel.role == .host)
        #expect(viewModel.connectionState == .advertising)
    }

    @Test func hostResolvesItsOwnChosenRoleImmediately() {
        // The host doesn't wait on any message for this — it knows its own choice right away.
        let viewModel = PeerConnectionViewModel(recipe: SampleRecipes.scrambledEggs)

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
        let viewModel = PeerConnectionViewModel(recipe: SampleRecipes.scrambledEggs)

        viewModel.join()

        #expect(viewModel.role == .joiner)
        #expect(viewModel.connectionState == .browsing)
    }

    @Test func cancelTearsDownTheUnderlyingConnection() {
        let viewModel = PeerConnectionViewModel(recipe: SampleRecipes.scrambledEggs)
        viewModel.host(as: .personA)
        #expect(viewModel.connectionState == .advertising)

        viewModel.cancel()

        #expect(viewModel.connectionState == .idle)
    }

    // MARK: - hostDidConnect (synchronous — no dispatch involved)

    @Test func hostDidConnectSetsDidHandshakeWhenHosting() {
        let viewModel = PeerConnectionViewModel(recipe: SampleRecipes.scrambledEggs)
        viewModel.host(as: .personA)
        #expect(!viewModel.didHandshake)

        viewModel.hostDidConnect()

        #expect(viewModel.didHandshake)
    }

    @Test func hostDidConnectDoesNothingBeforeHostIsCalled() {
        // Guards against a stray/late callback firing before `host()` has even set `role`.
        let viewModel = PeerConnectionViewModel(recipe: SampleRecipes.scrambledEggs)

        viewModel.hostDidConnect()

        #expect(!viewModel.didHandshake)
    }

    @Test func hostDidConnectDoesNothingForAJoiner() {
        // The joiner's handshake signal is the incoming `recipeSync` message, not this method —
        // it should be a no-op if role is `.joiner`.
        let viewModel = PeerConnectionViewModel(recipe: SampleRecipes.scrambledEggs)
        viewModel.join()

        viewModel.hostDidConnect()

        #expect(!viewModel.didHandshake)
    }

    @Test func hostDidConnectIsIdempotentOnceAlreadyHandshaken() {
        let viewModel = PeerConnectionViewModel(recipe: SampleRecipes.scrambledEggs)
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
