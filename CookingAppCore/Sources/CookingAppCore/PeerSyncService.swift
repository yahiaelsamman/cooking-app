import Foundation
import MultipeerConnectivity
import Observation

/// Bonjour service type for local peer discovery. Must be lowercase letters/digits/hyphens, <=15 chars.
private let serviceType = "cook-sync"

/// Wraps MultipeerConnectivity to sync cooking progress between exactly two nearby peers.
/// Networking is strictly additive: local step navigation must keep working with no peer
/// connected at all, so nothing in this service ever blocks the caller.
///
/// Delegate callbacks below are thin `DispatchQueue.main.async` wrappers around `internal`
/// (not `private`) handler methods — MultipeerConnectivity calls delegates on an arbitrary
/// queue, so production code needs the dispatch, but tests can call the synchronous handlers
/// directly (via `@testable import`) without needing a real MC session or waiting on the main
/// queue to drain.
@Observable
public final class PeerSyncService: NSObject {
    public private(set) var connectionState: ConnectionState = .idle
    public private(set) var partnerStepIndex: Int?
    public private(set) var partnerRecipeID: UUID?
    public private(set) var discoveredPeers: [MCPeerID] = []
    public private(set) var connectedPeerName: String?

    public var onRecipeSync: ((UUID) -> Void)?
    /// `(stepIndex in partner's own track, total duration in seconds)`.
    public var onPartnerTimerStarted: ((Int, Int) -> Void)?
    /// `stepIndex` in the partner's own track.
    public var onPartnerTimerCancelled: ((Int) -> Void)?
    /// Fired when the partner explicitly ends the session (as opposed to just dropping out of
    /// range, which triggers auto-reconnect instead — see `handleSessionStateChange`).
    public var onPartnerLeft: (() -> Void)?

    private let myPeerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var role: PeerRole?

    /// Set the first time this session reaches `.connected`. Once true, a later drop attempts
    /// automatic reconnection instead of leaving the user stranded on the step-through screen —
    /// they shouldn't have to back out to the connect screen just because a phone briefly lost
    /// WiFi/Bluetooth range mid-cook.
    private var hasConnectedBefore = false
    /// While true, a newly discovered peer is invited immediately rather than waiting for a tap
    /// in the (no longer visible) peer list — set only once we're trying to recover a session
    /// that had already succeeded before.
    private var autoReconnecting = false

    public init(displayName: String = ProcessInfo.processInfo.hostName) {
        self.myPeerID = MCPeerID(displayName: displayName)
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        super.init()
        session.delegate = self
    }

    // MARK: - Hosting (Person A)

    public func startHosting(recipeID: UUID) {
        role = .host
        partnerRecipeID = recipeID
        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        connectionState = .advertising
    }

    // MARK: - Joining (Person B)

    public func startBrowsing() {
        role = .joiner
        let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        connectionState = .browsing
        discoveredPeers = []
    }

    public func invite(peer: MCPeerID, timeout: TimeInterval = 10) {
        connectionState = .connecting
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: timeout)
    }

    // MARK: - Sending

    public func sendProgress(stepIndex: Int) {
        send(.progressUpdate(stepIndex: stepIndex))
    }

    public func sendTimerStarted(stepIndex: Int, durationSeconds: Int) {
        send(.timerStarted(stepIndex: stepIndex, durationSeconds: durationSeconds))
    }

    public func sendTimerCancelled(stepIndex: Int) {
        send(.timerCancelled(stepIndex: stepIndex))
    }

    private func sendRecipeSync(recipeID: UUID) {
        send(.recipeSync(recipeID: recipeID))
    }

    private func send(_ message: SyncMessage) {
        guard connectionState == .connected, !session.connectedPeers.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    // MARK: - Teardown

    /// A deliberate, user-initiated end to the session — tells the partner first (best-effort;
    /// this can't be guaranteed to arrive if the connection is already degrading) and then
    /// fully tears down locally with no auto-reconnect attempt. Contrast with a connection just
    /// dropping, which `attemptAutoReconnect` tries to recover from instead.
    ///
    /// No separate "is this deliberate" flag is needed to suppress auto-reconnect: `stop()`
    /// below resets `hasConnectedBefore` to `false` synchronously, and that happens before the
    /// framework's own (always-async) `.notConnected` callback for the resulting disconnect can
    /// possibly arrive — so `handleSessionStateChange`'s auto-reconnect guard already sees a
    /// clean slate by the time it runs.
    public func leaveSession() {
        send(.leaveSession())
        stop()
    }

    public func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
        advertiser = nil
        browser = nil
        connectionState = .idle
        discoveredPeers = []
        connectedPeerName = nil
        hasConnectedBefore = false
        autoReconnecting = false
        role = nil
        partnerStepIndex = nil
        partnerRecipeID = nil
    }

    // MARK: - Auto-reconnect

    /// Called when the peer drops after a previously-successful connection. Re-opens
    /// advertising (host) or browsing (joiner) so the other phone reappearing nearby
    /// reconnects automatically, without the user having to navigate back to the connect screen.
    private func attemptAutoReconnect() {
        switch role {
        case .host:
            advertiser?.stopAdvertisingPeer()
            advertiser?.startAdvertisingPeer()
        case .joiner:
            autoReconnecting = true
            discoveredPeers = []
            browser?.stopBrowsingForPeers()
            browser?.startBrowsingForPeers()
        case nil:
            break
        }
    }

    // MARK: - Testable synchronous handlers

    // These contain the actual logic for each delegate callback. The delegate methods below
    // dispatch to these on the main queue for production use; tests call them directly.

    func handleSessionStateChange(_ state: MCSessionState, peerID: MCPeerID) {
        switch state {
        case .connected:
            connectionState = .connected
            connectedPeerName = peerID.displayName
            hasConnectedBefore = true
            autoReconnecting = false
            // Resync current progress immediately so a reconnect self-heals both sides
            // without needing to track/replay any messages that were missed while apart.
            if role == .host, let recipeID = partnerRecipeID {
                sendRecipeSync(recipeID: recipeID)
            }
        case .connecting:
            connectionState = .connecting
        case .notConnected:
            connectionState = .disconnected
            connectedPeerName = nil
            if hasConnectedBefore {
                attemptAutoReconnect()
            }
        @unknown default:
            break
        }
    }

    func handleReceivedMessage(_ message: SyncMessage) {
        switch message.type {
        case .recipeSync:
            if let recipeID = message.recipeID {
                partnerRecipeID = recipeID
                onRecipeSync?(recipeID)
            }
        case .progressUpdate:
            partnerStepIndex = message.stepIndex
        case .timerStarted:
            if let stepIndex = message.stepIndex, let duration = message.timerDurationSeconds {
                onPartnerTimerStarted?(stepIndex, duration)
            }
        case .timerCancelled:
            if let stepIndex = message.stepIndex {
                onPartnerTimerCancelled?(stepIndex)
            }
        case .leaveSession:
            onPartnerLeft?()
            stop()
        }
    }

    func handleFoundPeer(_ peerID: MCPeerID) {
        if !discoveredPeers.contains(peerID) {
            discoveredPeers.append(peerID)
        }
        if autoReconnecting {
            invite(peer: peerID)
        }
    }

    func handleLostPeer(_ peerID: MCPeerID) {
        discoveredPeers.removeAll { $0 == peerID }
    }
}

// MARK: - MCSessionDelegate

extension PeerSyncService: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.handleSessionStateChange(state, peerID: peerID)
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(SyncMessage.self, from: data) else { return }
        DispatchQueue.main.async {
            self.handleReceivedMessage(message)
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension PeerSyncService: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PeerSyncService: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            self.handleFoundPeer(peerID)
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.handleLostPeer(peerID)
        }
    }
}
