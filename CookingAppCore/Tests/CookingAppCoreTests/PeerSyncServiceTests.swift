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
///
/// `@MainActor`: `PeerSyncService` is `@MainActor` (see its doc comment), so every call below —
/// including construction — needs to run on the main actor too.
@MainActor
struct PeerSyncServiceTests {

    private func makeService() -> PeerSyncService {
        PeerSyncService(displayName: "test-device")
    }

    // MARK: - Connection state transitions

    @Test func connectingThenConnectedUpdatesState() {
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startBrowsing() // role must be set before .connected is legitimate — see the stray-connection guard below

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

    @Test func dropAfterConnectingAsHostTriggersAutoReconnectAdvertising() {
        // Symmetric to the joiner path above: the host side of `attemptAutoReconnect` restarts
        // advertising rather than browsing, and never touches `discoveredPeers` (that's a
        // joiner-only concept — a host never browses for anyone).
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startHosting(recipeID: UUID(), hostRole: .personA) // role = .host
        service.handleSessionStateChange(.connected, peerID: peer)
        #expect(service.connectionState == .connected)

        service.handleSessionStateChange(.notConnected, peerID: peer)

        #expect(service.connectionState == .disconnected)
        #expect(service.discoveredPeers.isEmpty)

        // A rediscovered peer while auto-reconnecting as host should NOT be auto-invited (only
        // the joiner side auto-invites; the host just keeps advertising and waits).
        service.handleFoundPeer(peer)
        #expect(service.connectionState == .disconnected)
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
        service.startHosting(recipeID: UUID(), hostRole: .personA)
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

        service.handleReceivedMessage(.recipeSync(recipeID: recipeID, hostRole: .personA, senderName: "Alex"))

        #expect(service.partnerRecipeID == recipeID)
        #expect(callbackRecipeID == recipeID)
    }

    @Test func receivingRecipeSyncResolvesMyRoleAsTheOppositeOfTheHosts() {
        // I'm the joiner (never called startHosting) — the host chose Person A for themselves,
        // so I should resolve to Person B.
        let service = makeService()
        service.startBrowsing()

        service.handleReceivedMessage(.recipeSync(recipeID: UUID(), hostRole: .personA, senderName: "Alex"))

        #expect(service.resolvedStepAssignee == .personB)
    }

    @Test func receivingRecipeSyncResolvesMyRoleAsPersonAWhenHostChosePersonB() {
        let service = makeService()
        service.startBrowsing()

        service.handleReceivedMessage(.recipeSync(recipeID: UUID(), hostRole: .personB, senderName: "Alex"))

        #expect(service.resolvedStepAssignee == .personA)
    }

    @Test func startHostingResolvesMyOwnRoleImmediately() {
        // The host doesn't need to wait on any message — it already knows its own role the
        // moment it starts hosting.
        let service = makeService()

        service.startHosting(recipeID: UUID(), hostRole: .personB)

        #expect(service.resolvedStepAssignee == .personB)
    }

    @Test func receivingRecipeSyncStoresThePartnersName() {
        let service = makeService()
        service.startBrowsing()

        service.handleReceivedMessage(.recipeSync(recipeID: UUID(), hostRole: .personA, senderName: "Alex"))

        #expect(service.partnerName == "Alex")
    }

    @Test func receivingIntroduceStoresThePartnersName() {
        // The reverse direction — the joiner tells the host its name via `introduce`.
        let service = makeService()

        service.handleReceivedMessage(.introduce(name: "Sam"))

        #expect(service.partnerName == "Sam")
    }

    @Test func receivingPresenceUpdateSetsPartnerIsAway() {
        let service = makeService()
        #expect(!service.partnerIsAway)

        service.handleReceivedMessage(.presenceUpdate(isAway: true))
        #expect(service.partnerIsAway)

        service.handleReceivedMessage(.presenceUpdate(isAway: false))
        #expect(!service.partnerIsAway)
    }

    @Test func reachingConnectedResetsPartnerIsAway() {
        // A fresh (re)connect should assume presence until told otherwise, even if the partner
        // was marked away right before the drop.
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startBrowsing()
        service.handleReceivedMessage(.presenceUpdate(isAway: true))
        #expect(service.partnerIsAway)

        service.handleSessionStateChange(.connected, peerID: peer)

        #expect(!service.partnerIsAway)
    }

    @Test func onConnectedFiresOnTheInitialConnectAndEveryReconnect() {
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startHosting(recipeID: UUID(), hostRole: .personA)
        var connectedCount = 0
        service.onConnected = { connectedCount += 1 }

        service.handleSessionStateChange(.connected, peerID: peer)
        #expect(connectedCount == 1)

        service.handleSessionStateChange(.notConnected, peerID: peer) // triggers auto-reconnect
        service.handleSessionStateChange(.connected, peerID: peer) // the reconnect itself

        #expect(connectedCount == 2)
    }

    @Test func aStrayConnectedCallbackAfterStopIsRefusedRatherThanResurrectingState() {
        // Regression guard for "ending the session still leaves it joinable": `role` is only
        // non-nil between start*/stop, so a late `.connected` callback arriving after a
        // deliberate `stop()` must be refused, not accepted.
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")
        service.startHosting(recipeID: UUID(), hostRole: .personA)
        service.handleSessionStateChange(.connected, peerID: peer)
        service.stop()

        var connectedFired = false
        service.onConnected = { connectedFired = true }
        service.handleSessionStateChange(.connected, peerID: peer)

        #expect(service.connectionState == .idle)
        #expect(!connectedFired)
    }

    @Test func aStrayConnectedCallbackBeforeEverStartingIsAlsoRefused() {
        // Same guard, but for a `PeerSyncService` that was never hosted/joined at all.
        let service = makeService()
        let peer = MCPeerID(displayName: "partner-device")

        service.handleSessionStateChange(.connected, peerID: peer)

        #expect(service.connectionState == .idle)
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
        service.startHosting(recipeID: UUID(), hostRole: .personA)
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
