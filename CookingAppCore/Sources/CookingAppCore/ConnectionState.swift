/// Where a `PeerSyncService` is in the two-person connection lifecycle.
///
/// - `idle`: not hosting, browsing, or connected — the initial state, and where `disconnect()` lands.
/// - `advertising`: the host is visible to nearby phones and waiting for a partner to join.
/// - `browsing`: the joiner is searching for a nearby host's advertisement.
/// - `connecting`: an invitation was sent or accepted and the session is negotiating.
/// - `connected`: the peer session is established and messages can flow.
/// - `disconnected`: a connection that was established (or being negotiated) dropped. Distinct
///   from `idle` because it can trigger automatic reconnection after a previously successful
///   session, rather than meaning "never connected".
public enum ConnectionState: Equatable, Sendable {
    case idle
    case advertising
    case browsing
    case connecting
    case connected
    case disconnected
}
