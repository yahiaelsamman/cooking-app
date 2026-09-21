import Foundation
import os

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
    /// Optional so snapshots saved before this existed still decode (they mean "not scaled").
    public let servingsScaleFactor: Double?
    /// Optional for the same reason: older snapshots have no ticked ingredients.
    public let checkedIngredientNames: [String]?

    public init(recipeID: UUID, role: StepAssignee?, currentIndex: Int, timers: [TimerSnapshot], servingsScaleFactor: Double? = nil, checkedIngredientNames: [String]? = nil) {
        self.recipeID = recipeID
        self.role = role
        self.currentIndex = currentIndex
        self.timers = timers
        self.servingsScaleFactor = servingsScaleFactor
        self.checkedIngredientNames = checkedIngredientNames
    }
}

/// Persists the single active `CookingSessionSnapshot` (if any) to `UserDefaults` — the payload is
/// a few dozen bytes at most, nowhere near what would justify a file-based store.
public enum SessionPersistence {
    private static let key = "activeCookingSessionSnapshot"
    private static let logger = Logger(subsystem: "com.yahia.cookingapp", category: "SessionPersistence")

    public static func save(_ snapshot: CookingSessionSnapshot, defaults: UserDefaults = .standard) {
        // Lower stakes than a `RecipeSeeder` failure (this only affects "resume cooking after a
        // force-quit," never the recipe data itself), but still logged rather than silently
        // dropped — a save failure here means the *next* launch quietly loses "resume cooking"
        // with no signal anything went wrong.
        guard let data = try? JSONEncoder().encode(snapshot) else {
            logger.error("Failed to encode a CookingSessionSnapshot for saving.")
            return
        }
        defaults.set(data, forKey: key)
    }

    public static func load(defaults: UserDefaults = .standard) -> CookingSessionSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(CookingSessionSnapshot.self, from: data)
        } catch {
            logger.error("Failed to decode the saved CookingSessionSnapshot: \(error, privacy: .public)")
            return nil
        }
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
