public enum ConnectionState: Equatable, Sendable {
    case idle
    case advertising
    case browsing
    case connecting
    case connected
    case disconnected
}
