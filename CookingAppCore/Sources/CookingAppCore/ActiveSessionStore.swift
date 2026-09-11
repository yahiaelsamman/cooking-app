import Observation

/// Holds a reference to whatever cooking session is currently in progress, independent of
/// navigation. Lets the app show a "resume cooking" affordance from the recipe list and jump
/// straight back into the *same* `CookingSessionViewModel` instance — preserving `currentIndex`,
/// any running timers, and (for two-person sessions) the peer connection and role, rather than
/// re-navigating through the recipe/connect flow and risking a Person A/B role flip.
///
/// This is in-memory only: it survives navigating away from the step screen and backgrounding
/// the app (as long as the process stays alive), but not an actual app termination — there's no
/// disk persistence in this MVP, so a force-quit still loses the session.
@Observable
public final class ActiveSessionStore {
    public private(set) var currentSession: CookingSessionViewModel?

    public init() {}

    public var hasActiveSession: Bool { currentSession != nil }

    public func setActive(_ session: CookingSessionViewModel) {
        currentSession = session
    }

    public func clear() {
        currentSession = nil
    }
}
