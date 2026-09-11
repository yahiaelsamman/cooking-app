import Foundation
import MultipeerConnectivity
import Observation

/// Bonjour service type for local peer discovery. Must be lowercase letters/digits/hyphens, <=15 chars.
private let serviceType = "cook-sync"

/// Wraps MultipeerConnectivity to sync cooking progress between exactly two nearby peers.
/// Networking is strictly additive: local step navigation must keep working with no peer
/// connected at all, so nothing in this service ever blocks the caller.
@Observable
public final class PeerSyncService: NSObject {
    public private(set) var connectionState: ConnectionState = .idle
    public private(set) var partnerStepIndex: Int?
    public private(set) var partnerRecipeID: UUID?
    public private(set) var discoveredPeers: [MCPeerID] = []
    public private(set) var connectedPeerName: String?

    public var onRecipeSync: ((UUID) -> Void)?

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
        guard connectionState == .connected, !session.connectedPeers.isEmpty else { return }
        send(.progressUpdate(stepIndex: stepIndex))
    }

    private func sendRecipeSync(recipeID: UUID) {
        send(.recipeSync(recipeID: recipeID))
    }

    private func send(_ message: SyncMessage) {
        guard !session.connectedPeers.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    // MARK: - Teardown

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
}

// MARK: - MCSessionDelegate

extension PeerSyncService: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectionState = .connected
                self.connectedPeerName = peerID.displayName
                self.hasConnectedBefore = true
                self.autoReconnecting = false
                // Resync current progress immediately so a reconnect self-heals both sides
                // without needing to track/replay any messages that were missed while apart.
                if self.role == .host, let recipeID = self.partnerRecipeID {
                    self.sendRecipeSync(recipeID: recipeID)
                }
            case .connecting:
                self.connectionState = .connecting
            case .notConnected:
                self.connectionState = .disconnected
                self.connectedPeerName = nil
                if self.hasConnectedBefore {
                    self.attemptAutoReconnect()
                }
            @unknown default:
                break
            }
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(SyncMessage.self, from: data) else { return }
        DispatchQueue.main.async {
            switch message.type {
            case .recipeSync:
                if let recipeID = message.recipeID {
                    self.partnerRecipeID = recipeID
                    self.onRecipeSync?(recipeID)
                }
            case .progressUpdate:
                self.partnerStepIndex = message.stepIndex
            }
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
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
            }
            if self.autoReconnecting {
                self.invite(peer: peerID)
            }
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
        }
    }
}
