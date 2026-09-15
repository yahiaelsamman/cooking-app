import Foundation
import MultipeerConnectivity
import Observation

/// Drives the host/join connection screen shown before a two-person cooking session starts.
@Observable
public final class PeerConnectionViewModel {
    public let recipe: Recipe
    public let peerSync: PeerSyncService

    public private(set) var didHandshake = false
    public private(set) var role: PeerRole?

    public init(recipe: Recipe, peerSync: PeerSyncService = PeerSyncService()) {
        self.recipe = recipe
        self.peerSync = peerSync
        peerSync.onRecipeSync = { [weak self] receivedRecipeID in
            guard let self, self.role == .joiner, receivedRecipeID == self.recipe.id else { return }
            DispatchQueue.main.async { self.didHandshake = true }
        }
    }

    public var connectionState: ConnectionState { peerSync.connectionState }
    public var discoveredPeers: [MCPeerID] { peerSync.discoveredPeers }
    /// My resolved cooking role: for the host, whatever they picked in `host(as:)`; for the
    /// joiner, the opposite of the host's choice, learned once `recipeSync` arrives. `nil` until
    /// then — `didHandshake` only flips true once this is already resolved (for the joiner, both
    /// happen off the same incoming `recipeSync` message; for the host, `resolvedStepAssignee` is
    /// set synchronously in `host(as:)`, before hosting even starts).
    public var resolvedStepAssignee: StepAssignee? { peerSync.resolvedStepAssignee }
    public var partnerName: String? { peerSync.partnerName }

    /// - Parameter role: which cooking role the host wants to be — chosen via a toggle on the
    ///   connect screen before hosting. The joiner is assigned the opposite once connected.
    public func host(as role: StepAssignee) {
        self.role = .host
        peerSync.startHosting(recipeID: recipe.id, hostRole: role)
    }

    public func join() {
        role = .joiner
        peerSync.startBrowsing()
    }

    public func connect(to peer: MCPeerID) {
        peerSync.invite(peer: peer)
    }

    /// The host has no `recipeSync` message to wait on (it sends that message, it doesn't
    /// receive one) — call this when the view observes the underlying session reaching
    /// `.connected` while hosting. Guarded so a later disconnect/reconnect during an
    /// already-active cook session never re-triggers navigation.
    public func hostDidConnect() {
        guard role == .host, !didHandshake else { return }
        didHandshake = true
    }

    public func cancel() {
        peerSync.stop()
    }
}
