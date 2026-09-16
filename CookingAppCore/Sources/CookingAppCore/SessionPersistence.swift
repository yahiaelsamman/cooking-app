import Foundation

/// One timer that was running when a solo session was last persisted. Stores an absolute
/// `endDate` rather than a `remainingSeconds` count — a force-quit can last anywhere from seconds
/// to hours, so remaining time has to be recomputed from real elapsed time on restore, the same
/// way `NotificationScheduler` already fires a local notification for a backgrounded timer
/// instead of assuming the app is still alive to tick it down itself.
public struct TimerSnapshot: Codable, Equatable, Sendable {
    public let stepID: UUID
    public let totalSeconds: Int
    public let endDate: Date

    public init(stepID: UUID, totalSeconds: Int, endDate: Date) {
        self.stepID = stepID
        self.totalSeconds = totalSeconds
        self.endDate = endDate
    }
}

/// Everything needed to reconstruct a solo `CookingSessionViewModel` after the app process itself
/// has been killed and relaunched. Two-person sessions are deliberately never snapshotted — see
/// `ActiveSessionStore`'s doc comment — so `role` only exists here for symmetry/future use and is
/// always `nil` in practice today.
public struct CookingSessionSnapshot: Codable, Equatable, Sendable {
    public let recipeID: UUID
    public let role: StepAssignee?
    public let currentIndex: Int
    public let timers: [TimerSnapshot]

    public init(recipeID: UUID, role: StepAssignee?, currentIndex: Int, timers: [TimerSnapshot]) {
        self.recipeID = recipeID
        self.role = role
        self.currentIndex = currentIndex
        self.timers = timers
    }
}

/// Persists the single active `CookingSessionSnapshot` (if any) to `UserDefaults` — the payload is
/// a few dozen bytes at most, nowhere near what would justify a file-based store.
public enum SessionPersistence {
    private static let key = "activeCookingSessionSnapshot"

    public static func save(_ snapshot: CookingSessionSnapshot, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    public static func load(defaults: UserDefaults = .standard) -> CookingSessionSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CookingSessionSnapshot.self, from: data)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
