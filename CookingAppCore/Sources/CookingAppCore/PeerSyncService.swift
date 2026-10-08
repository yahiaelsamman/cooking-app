import Foundation
import MultipeerConnectivity
import Observation

/// Bonjour service type for local peer discovery. Must be lowercase letters/digits/hyphens, <=15 chars.
private let serviceType = "cook-sync"

/// Wraps MultipeerConnectivity to sync cooking progress between exactly two nearby peers.
/// Networking is strictly additive: local step navigation must keep working with no peer
/// connected at all, so nothing in this service ever blocks the caller.
///
/// The service itself is `@MainActor` — every stored property here is read/written from SwiftUI
/// bindings and `CookingSessionViewModel`/`PeerConnectionViewModel` (both `@MainActor` too), so
/// this makes that existing convention compiler-checked instead of just documented. The three
/// `MCSessionDelegate`/`MCNearbyServiceAdvertiserDelegate`/`MCNearbyServiceBrowserDelegate`
/// extensions below are the one place that can't follow that isolation directly:
/// MultipeerConnectivity calls delegate methods on an arbitrary queue, not the main actor, so
/// those specific methods stay `nonisolated` and hop onto the main actor explicitly (`Task {
/// @MainActor in ... }`) to reach the `internal` (not `private`) handler methods that hold the
/// actual logic — `handleSessionStateChange`, `handleReceivedMessage`, `handleFoundPeer`,
/// `handleLostPeer`. Those handlers are `@MainActor` like the rest of the class; tests call them
/// directly (via `@testable import`) from a `@MainActor` test suite, so no real MC session or
/// run-loop spin is needed to exercise them synchronously.
@Observable
@MainActor
public final class PeerSyncService: NSObject {
    public private(set) var connectionState: ConnectionState = .idle
    public private(set) var partnerStepIndex: Int?
    public private(set) var partnerRecipeID: UUID?
    public private(set) var discoveredPeers: [MCPeerID] = []
    public private(set) var connectedPeerName: String?
    /// The partner's chosen display name, learned via `recipeSync` (host → joiner) or `introduce`
    /// (joiner → host) — `nil` until that round-trip completes.
    public private(set) var partnerName: String?
    /// My own cooking role once resolved: for the host, whatever they picked in `startHosting`;
    /// for the joiner, the opposite of the host's `recipeSync.hostRole`. `nil` until then.
    public private(set) var resolvedStepAssignee: StepAssignee?
    /// True once the partner has sent a `presenceUpdate(isAway: true)` — they're still connected,
    /// just not currently looking at the step screen (e.g. they backed out to the recipe
    /// overview). Distinct from `connectionState == .disconnected`, which means the underlying
    /// connection actually dropped.
    public private(set) var partnerIsAway = false
    /// Human-readable reason hosting/browsing could not start (e.g. Local Network permission
    /// denied, or Bluetooth/Wi-Fi off). `nil` when nothing has failed; cleared on the next start.
    public private(set) var startFailure: String?

    public var onRecipeSync: ((UUID) -> Void)?
    /// `(stepIndex in partner's own track, total duration in seconds)`.
    public var onPartnerTimerStarted: ((Int, Int) -> Void)?
    /// `stepIndex` in the partner's own track.
    public var onPartnerTimerCancelled: ((Int) -> Void)?
    /// The partner's full set of running timers; the receiver should replace its mirror with it.
    public var onPartnerTimerSnapshot: (([TimerSnapshotEntry]) -> Void)?
    /// Fired when the partner explicitly ends the session (as opposed to just dropping out of
    /// range, which triggers auto-reconnect instead — see `handleSessionStateChange`).
    public var onPartnerLeft: (() -> Void)?
    /// Fired every time `connectionState` reaches `.connected` — on the very first handshake AND
    /// on every later reconnect. `CookingSessionViewModel` uses this to re-announce its current
    /// step/timers, since a reconnect otherwise carries no information about where either side
    /// actually is (only `advance()`/`goBack()`/`startTimer()` send anything, and a reconnect
    /// triggers none of those on its own).
    public var onConnected: (() -> Void)?

    private let myPeerID: MCPeerID
    private let myDisplayName: String
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var role: PeerRole?
    /// True between `stop()` and the next `startHosting`/`startBrowsing`.
    private var isStopped = false
    /// Set only by the host, via `startHosting(hostRole:)` — what to send as `hostRole` on the
    /// next `recipeSync`.
    private var hostChosenRole: StepAssignee?

    /// Set the first time this session reaches `.connected`. Once true, a later drop attempts
    /// automatic reconnection instead of leaving the user stranded on the step-through screen —
    /// they shouldn't have to back out to the connect screen just because a phone briefly lost
    /// WiFi/Bluetooth range mid-cook.
    private var hasConnectedBefore = false
    /// While true, a newly discovered peer is invited immediately rather than waiting for a tap
    /// in the (no longer visible) peer list — set only once we're trying to recover a session
    /// that had already succeeded before.
    private var autoReconnecting = false
    /// The one phone this session is paired with, set on the first `.connected`. State changes from
    /// any other peer are ignored, and auto-reconnect only re-invites this partner.
    private var partnerPeerID: MCPeerID?
    /// The recipe the joiner is cooking. Hosts advertise theirs in `discoveryInfo`, so a joiner
    /// only lists hosts cooking the same recipe.
    private var browseRecipeID: UUID?

    /// `MCPeerID` traps on a display name over 63 UTF-8 bytes, and the cook's name has no length limit.
    static func peerDisplayName(_ name: String) -> String {
        var result = ""
        for character in name {
            guard result.utf8.count + String(character).utf8.count <= 63 else { break }
            result.append(character)
        }
        return result.isEmpty ? "Cook" : result
    }

    public init(displayName: String = "Cook") {
        let displayName = Self.peerDisplayName(displayName)
        self.myPeerID = MCPeerID(displayName: displayName)
        self.myDisplayName = displayName
        // `.none` is deliberate: the only payload is a recipe's steps and progress indices over a
        // short-range, in-person link — nothing sensitive — and skipping the TLS handshake keeps
        // pairing fast and avoids `.required`/`.optional` mismatches failing connections silently.
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        super.init()
        session.delegate = self
    }

    // MARK: - Hosting

    /// - Parameter hostRole: the cooking role the host picked for themselves (via the host-side
    ///   toggle) — sent to the joiner in `recipeSync` so they can resolve their own role as the
    ///   opposite, rather than a role being hardcoded to "host."
    public func startHosting(recipeID: UUID, hostRole: StepAssignee) {
        role = .host
        isStopped = false
        startFailure = nil
        hostChosenRole = hostRole
        resolvedStepAssignee = hostRole
        partnerRecipeID = recipeID
        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: [Self.recipeInfoKey: recipeID.uuidString], serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        connectionState = .advertising
    }

    // MARK: - Joining

    static let recipeInfoKey = "recipe"

    /// - Parameter recipeID: when set, hosts advertising a different recipe aren't listed.
    public func startBrowsing(recipeID: UUID? = nil) {
        role = .joiner
        isStopped = false
        startFailure = nil
        browseRecipeID = recipeID
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

    public func sendTimerSnapshot(_ timers: [TimerSnapshotEntry]) {
        send(.timerSnapshot(timers))
    }

    /// "Stepped away" (backed out to the recipe overview, still connected) vs. "returned" — a
    /// softer signal than an actual drop, purely for the partner's status display.
    public func sendPresenceUpdate(isAway: Bool) {
        send(.presenceUpdate(isAway: isAway))
    }

    private func sendRecipeSync(recipeID: UUID, hostRole: StepAssignee) {
        send(.recipeSync(recipeID: recipeID, hostRole: hostRole, senderName: myDisplayName))
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
    ///
    /// The actual `session.disconnect()` is delayed briefly: MultipeerConnectivity can drop a
    /// reliable send that is still queued when the session disconnects, and the partner would
    /// then see a plain drop and try to reconnect to a phone that is gone.
    public func leaveSession() {
        let wasConnected = connectionState == .connected
        send(.leaveSession())
        stop(disconnectDelay: wasConnected ? Self.leaveDisconnectDelay : 0)
    }

    static let leaveDisconnectDelay: TimeInterval = 0.7

    public func stop() {
        stop(disconnectDelay: 0)
    }

    private func stop(disconnectDelay: TimeInterval) {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        if disconnectDelay > 0 {
            let session = self.session
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(disconnectDelay))
                // A new session may have started in the meantime; leave that one alone.
                if self?.role == nil { session.disconnect() }
            }
        } else {
            session.disconnect()
        }
        advertiser = nil
        browser = nil
        connectionState = .idle
        discoveredPeers = []
        connectedPeerName = nil
        hasConnectedBefore = false
        autoReconnecting = false
        partnerPeerID = nil
        browseRecipeID = nil
        role = nil
        hostChosenRole = nil
        resolvedStepAssignee = nil
        partnerName = nil
        partnerIsAway = false
        partnerStepIndex = nil
        partnerRecipeID = nil
        startFailure = nil
        isStopped = true
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
            guard role != nil else {
                // A stray/late `.connected` callback arriving after a deliberate `stop()` (role
                // is only non-nil between start*/stop) — refuse it rather than resurrecting
                // connected state, so an ended session can't be silently rejoined.
                session.disconnect()
                return
            }
            if partnerPeerID == nil { partnerPeerID = peerID }
            // Paired: stop being discoverable / looking, so a third phone can't join in.
            // `attemptAutoReconnect` restarts whichever one this side uses if the link drops.
            advertiser?.stopAdvertisingPeer()
            browser?.stopBrowsingForPeers()
            connectionState = .connected
            connectedPeerName = peerID.displayName
            hasConnectedBefore = true
            autoReconnecting = false
            partnerIsAway = false
            // Resync current progress immediately so a reconnect self-heals both sides
            // without needing to track/replay any messages that were missed while apart.
            if role == .host, let recipeID = partnerRecipeID, let hostChosenRole {
                sendRecipeSync(recipeID: recipeID, hostRole: hostChosenRole)
            }
            onConnected?()
        case .connecting:
            // A stale callback after leaveSession()/stop() must not resurrect a torn-down session.
            guard role != nil else { return }
            connectionState = .connecting
        case .notConnected:
            guard role != nil, isPartner(peerID) else { return }
            connectedPeerName = nil
            if hasConnectedBefore {
                connectionState = .disconnected
                attemptAutoReconnect()
            } else if partnerPeerID == nil {
                // A failed or timed-out invite: we are still advertising/browsing, so say so
                // rather than showing a misleading "disconnected".
                connectionState = (role == .host) ? .advertising : .browsing
            } else {
                connectionState = .disconnected
            }
        @unknown default:
            break
        }
    }

    func handleReceivedMessage(_ message: SyncMessage) {
        // A message hopped onto the main actor after stop() must not touch a torn-down service.
        guard !isStopped else { return }
        switch message.type {
        case .recipeSync:
            if let recipeID = message.recipeID {
                partnerRecipeID = recipeID
                onRecipeSync?(recipeID)
            }
            if let hostRole = message.hostRole, role != .host {
                resolvedStepAssignee = (hostRole == .personA) ? .personB : .personA
            }
            if let name = message.senderName {
                partnerName = name
            }
            // Tell the host our own name in return — recipeSync only carries the host's name,
            // since it's the one message the host doesn't have to wait on.
            send(.introduce(name: myDisplayName))
        case .introduce:
            if let name = message.senderName {
                partnerName = name
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
        case .timerSnapshot:
            onPartnerTimerSnapshot?(message.timers ?? [])
        case .presenceUpdate:
            if let isAway = message.isAway {
                partnerIsAway = isAway
            }
        case .leaveSession:
            onPartnerLeft?()
            stop()
        }
    }

    func handleFoundPeer(_ peerID: MCPeerID, discoveryInfo: [String: String]? = nil) {
        // Hosts on an older build advertise no recipe — still listed, and the recipeSync
        // check in `PeerConnectionViewModel` catches a mismatch after connecting.
        if let browseRecipeID, let advertised = discoveryInfo?[Self.recipeInfoKey],
           advertised != browseRecipeID.uuidString {
            return
        }
        if !discoveredPeers.contains(peerID) {
            discoveredPeers.append(peerID)
        }
        if autoReconnecting, isPartner(peerID) {
            invite(peer: peerID)
        }
    }

    /// True for the paired partner, or for anyone before pairing. Rediscovered peers are also
    /// matched by display name, in case the framework hands back a different `MCPeerID` instance.
    private func isPartner(_ peerID: MCPeerID) -> Bool {
        guard let partnerPeerID else { return true }
        return peerID == partnerPeerID || peerID.displayName == partnerPeerID.displayName
    }

    func handleStartFailure(_ error: Error, hosting: Bool) {
        guard role != nil else { return }
        let nsError = error as NSError
        let reason = hosting ? "Couldn't start hosting" : "Couldn't look for nearby phones"
        startFailure = "\(reason). Check that Local Network access is allowed for this app in Settings, and that Wi-Fi and Bluetooth are on. (\(nsError.localizedDescription))"
        connectionState = .idle
        if hosting { advertiser = nil } else { browser = nil }
    }

    func handleLostPeer(_ peerID: MCPeerID) {
        discoveredPeers.removeAll { $0 == peerID }
    }
}

// MARK: - MCSessionDelegate

extension PeerSyncService: MCSessionDelegate {
    public nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.handleSessionStateChange(state, peerID: peerID)
        }
    }

    public nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(SyncMessage.self, from: data) else { return }
        Task { @MainActor in
            self.handleReceivedMessage(message)
        }
    }

    public nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension PeerSyncService: MCNearbyServiceAdvertiserDelegate {
    public nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // `session` is main-actor-isolated storage, so it can only be read from inside the hop —
        // MCNearbyServiceAdvertiserDelegate explicitly allows calling `invitationHandler` later
        // rather than synchronously from this method, so deferring the accept by one run-loop
        // turn onto the main actor is within the API's contract, not a behavior change that
        // matters here.
        // Already paired with someone (or, after a drop, invited by anyone but that partner):
        // decline, so a session never grows past two phones.
        Task { @MainActor in
            invitationHandler(self.session.connectedPeers.isEmpty && self.isPartner(peerID), self.session)
        }
    }

    public nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.handleStartFailure(error, hosting: true)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PeerSyncService: MCNearbyServiceBrowserDelegate {
    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            self.handleFoundPeer(peerID, discoveryInfo: info)
        }
    }

    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.handleStartFailure(error, hosting: false)
        }
    }

    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.handleLostPeer(peerID)
        }
    }
}
