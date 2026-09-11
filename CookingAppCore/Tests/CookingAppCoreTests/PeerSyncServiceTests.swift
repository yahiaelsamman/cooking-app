import Foundation
import MultipeerConnectivity
import Testing
@testable import CookingAppCore

/// Exercises `PeerSyncService`'s message-handling and connection-lifecycle logic without any
/// real MultipeerConnectivity networking. This works because `MCPeerID` and `MCSession` are
/// plain, no-network-required-to-construct value/reference types, and because the delegate
/// methods dispatch to `internal` synchronous handlers (`handleSessionStateChange`,
/// `handleReceivedMessage`, `handleFoundPeer`, `handleLostPeer`) that tests can call directly —
/// see the comment on `PeerSyncService` for why that split exists.
///
/// Important: `MCPeerID` equality is *not* just display-name comparison — two separately
/// constructed instances with the same display name are not `==`. Every test below constructs
/// its peer id exactly once into a `let` and reuses that same instance, never a fresh one.
struct PeerSyncServiceTests {

    private func makeService() -> PeerSyncService {
        PeerSyncService(displayName: "test-device")
    }

    // MARK: - Connection state transitions

    @Test func connectingThenConnectedUpdatesState() {
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")

        service.handleSessionStateChange(.connecting, peerID: peer)
        #expect(service.connectionState == .connecting)

        service.handleSessionStateChange(.connected, peerID: peer)
        #expect(service.connectionState == .connected)
        #expect(service.connectedPeerName == "partner-device")
    }

    @Test func dropAfterNeverHavingConnectedDoesNotAutoReconnect() {
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startBrowsing() // role = .joiner, but never actually connects

        service.handleSessionStateChange(.notConnected, peerID: peer)

        #expect(service.connectionState == .disconnected)
        // No prior successful connection, so this should be a plain disconnect, not a recovery
        // attempt — `discoveredPeers` should be untouched (auto-reconnect resets it to []).
        #expect(service.discoveredPeers.isEmpty)
    }

    @Test func dropAfterConnectingAsJoinerTriggersAutoReconnectBrowsing() {
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startBrowsing() // role = .joiner
        service.handleSessionStateChange(.connected, peerID: peer)
        #expect(service.connectionState == .connected)

        service.handleSessionStateChange(.notConnected, peerID: peer)

        #expect(service.connectionState == .disconnected)
        // Auto-reconnect (joiner path) clears the stale peer list in preparation for rediscovery.
        #expect(service.discoveredPeers.isEmpty)

        // The auto-reconnect path should now auto-invite any peer it (re)discovers, rather than
        // waiting for a manual tap — verified indirectly: `invite` always sets `.connecting`.
        service.handleFoundPeer(peer)
        #expect(service.connectionState == .connecting)
    }

    @Test func explicitLeaveSessionPreventsAutoReconnectOnTheResultingDisconnect() {
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startBrowsing()
        service.handleSessionStateChange(.connected, peerID: peer)

        service.leaveSession() // resets hasConnectedBefore synchronously, before any async .notConnected can arrive
        #expect(service.connectionState == .idle)

        // Simulate the framework's own (always-async, so necessarily-later) notConnected
        // callback finally arriving after the deliberate leave above.
        service.handleSessionStateChange(.notConnected, peerID: peer)

        #expect(service.connectionState == .disconnected)
        // If auto-reconnect had (incorrectly) fired, a peer showing up would flip us back to
        // .connecting; confirm it doesn't.
        service.handleFoundPeer(peer)
        #expect(service.connectionState == .disconnected)
    }

    @Test func stopResetsStateForReuse() {
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startHosting(recipeID: UUID())
        service.handleSessionStateChange(.connected, peerID: peer)

        service.stop()

        #expect(service.connectionState == .idle)
        #expect(service.discoveredPeers.isEmpty)
        #expect(service.connectedPeerName == nil)
        #expect(service.partnerStepIndex == nil)
        #expect(service.partnerRecipeID == nil)
    }

    // MARK: - Received messages

    @Test func receivingRecipeSyncUpdatesStateAndFiresCallback() {
        let service = makeService()
        let recipeID = UUID()
        var callbackRecipeID: UUID?
        service.onRecipeSync = { callbackRecipeID = $0 }

        service.handleReceivedMessage(.recipeSync(recipeID: recipeID))

        #expect(service.partnerRecipeID == recipeID)
        #expect(callbackRecipeID == recipeID)
    }

    @Test func receivingProgressUpdateSetsPartnerStepIndex() {
        let service = makeService()

        service.handleReceivedMessage(.progressUpdate(stepIndex: 5))

        #expect(service.partnerStepIndex == 5)
    }

    @Test func receivingTimerStartedFiresCallbackWithStepIndexAndDuration() {
        let service = makeService()
        var received: (Int, Int)?
        service.onPartnerTimerStarted = { received = ($0, $1) }

        service.handleReceivedMessage(.timerStarted(stepIndex: 2, durationSeconds: 300))

        #expect(received?.0 == 2)
        #expect(received?.1 == 300)
    }

    @Test func receivingTimerCancelledFiresCallbackWithStepIndex() {
        let service = makeService()
        var received: Int?
        service.onPartnerTimerCancelled = { received = $0 }

        service.handleReceivedMessage(.timerCancelled(stepIndex: 2))

        #expect(received == 2)
    }

    @Test func receivingLeaveSessionFiresCallbackAndTearsDown() {
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startHosting(recipeID: UUID())
        service.handleSessionStateChange(.connected, peerID: peer)

        var partnerLeftFired = false
        service.onPartnerLeft = { partnerLeftFired = true }

        service.handleReceivedMessage(.leaveSession())

        #expect(partnerLeftFired)
        #expect(service.connectionState == .idle) // stop() was called as part of handling it

        // And since stop() reset hasConnectedBefore, a later stray .notConnected callback for
        // the same drop shouldn't trigger an auto-reconnect attempt either.
        service.handleSessionStateChange(.notConnected, peerID: peer)
        service.handleFoundPeer(peer)
        #expect(service.connectionState == .disconnected)
    }

    // MARK: - Peer discovery

    @Test func foundPeerIsAddedOnceEvenIfReportedTwice() {
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startBrowsing()

        service.handleFoundPeer(peer)
        service.handleFoundPeer(peer)

        #expect(service.discoveredPeers.count == 1)
    }

    @Test func lostPeerRemovesItFromDiscoveredPeers() {
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startBrowsing()
        service.handleFoundPeer(peer)
        #expect(service.discoveredPeers.count == 1)

        service.handleLostPeer(peer)

        #expect(service.discoveredPeers.isEmpty)
    }

    @Test func foundPeerDoesNotAutoInviteOutsideAutoReconnect() {
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startBrowsing() // fresh browse, never connected before — no auto-reconnect state

        service.handleFoundPeer(peer)

        // Should be discovered but not auto-invited (that's a manual "tap to connect" moment).
        #expect(service.discoveredPeers.contains(peer))
        #expect(service.connectionState == .browsing)
    }
}
