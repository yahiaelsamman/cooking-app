public enum PeerRole: Sendable {
    case host
    case joiner

    /// Host is always Person A, joiner is always Person B — no role-swap negotiation in the MVP.
    public var stepAssignee: StepAssignee {
        switch self {
        case .host: return .personA
        case .joiner: return .personB
        }
    }
}
