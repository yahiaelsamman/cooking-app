import Foundation
import Observation
import SwiftData

/// Holds a reference to whatever cooking session is currently in progress, independent of
/// navigation. Lets the app show a "resume cooking" affordance from the recipe list and jump
/// straight back into the *same* `CookingSessionViewModel` instance — preserving `currentIndex`,
/// any running timers, and (for two-person sessions) the peer connection and role, rather than
/// re-navigating through the recipe/connect flow and risking a Person A/B role flip.
///
/// A *solo* session also survives an actual app termination: every mutation is mirrored to a
/// `CookingSessionSnapshot` on disk (see `persist(_:)`/`SessionPersistence`), and `restoreIfNeeded`
/// rebuilds a live session from it at the next launch. Two-person sessions are deliberately never
/// snapshotted — the live `PeerSyncService`/MultipeerConnectivity session underneath one can't
/// survive termination anyway, and re-handshaking mid-recipe with a partner is a materially
/// different (and unbuilt) feature, so a force-quit still loses a shared session exactly as before.
///
/// `@MainActor`: constructed once as `@State` on the app's root view and handed around via
/// `.environment`, read/written only from SwiftUI — this makes that already-true convention
/// compiler-checked.
@Observable
@MainActor
public final class ActiveSessionStore {
    public private(set) var currentSession: CookingSessionViewModel?

    public init() {}

    public var hasActiveSession: Bool { currentSession != nil }

    public func setActive(_ session: CookingSessionViewModel) {
        currentSession = session
        guard session.role == nil else { return }
        session.onMutated = { [weak self, weak session] in
            guard let self, let session else { return }
            self.persist(session)
        }
        persist(session)
    }

    public func clear() {
        currentSession?.onMutated = nil
        currentSession = nil
        SessionPersistence.clear()
    }

    private func persist(_ session: CookingSessionViewModel) {
        let timers = session.activeTimers.map { timer in
            TimerSnapshot(
                stepID: timer.step.id,
                totalSeconds: timer.totalSeconds,
                endDate: Date().addingTimeInterval(TimeInterval(timer.remainingSeconds))
            )
        }
        let snapshot = CookingSessionSnapshot(
            recipeID: session.recipe.id,
            role: session.role,
            currentIndex: session.currentIndex,
            timers: timers
        )
        SessionPersistence.save(snapshot)
    }

    /// Called once at app launch (see `CookingAppApp.init`) to rebuild a persisted solo session, if
    /// there is one, so "Resume Cooking" survives a force-quit and not just backgrounding. A no-op
    /// if there's nothing persisted, its recipe no longer exists in the store, or (shouldn't happen
    /// today, since one is never written) it's a two-person snapshot.
    public func restoreIfNeeded(modelContext: ModelContext) {
        guard currentSession == nil, let snapshot = SessionPersistence.load(), snapshot.role == nil else { return }

        let recipeID = snapshot.recipeID
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == recipeID })
        guard let recipe = (try? modelContext.fetch(descriptor))?.first else {
            SessionPersistence.clear()
            return
        }

        // Timers store an absolute end date, not a remaining-seconds count — recompute against
        // real elapsed time, and simply drop anything that already finished while the app was
        // dead rather than restoring it as an (impossible) negative countdown.
        let soloTrack = recipe.track(for: nil)
        let timers: [ActiveTimer] = snapshot.timers.compactMap { timerSnapshot in
            let remaining = Int(timerSnapshot.endDate.timeIntervalSinceNow.rounded())
            guard remaining > 0, let step = soloTrack.first(where: { $0.id == timerSnapshot.stepID }) else { return nil }
            return ActiveTimer(step: step, totalSeconds: timerSnapshot.totalSeconds, remainingSeconds: remaining)
        }

        let session = CookingSessionViewModel(recipe: recipe)
        session.restoreState(currentIndex: snapshot.currentIndex, timers: timers)
        setActive(session)
    }
}
