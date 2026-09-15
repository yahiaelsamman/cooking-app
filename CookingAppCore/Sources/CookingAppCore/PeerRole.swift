/// The *network* role in a two-person connection — who advertised vs. who browsed/joined. This is
/// purely a MultipeerConnectivity-topology concept (it drives `PeerSyncService`'s auto-reconnect:
/// the host re-advertises, the joiner re-browses) and is intentionally decoupled from the
/// *cooking* role (`StepAssignee.personA`/`.personB`), which is chosen via a toggle on the host's
/// screen and resolved for the joiner from the host's choice — see `PeerSyncService.resolvedStepAssignee`.
public enum PeerRole: Sendable {
    case host
    case joiner
}
