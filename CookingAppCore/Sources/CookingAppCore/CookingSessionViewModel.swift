import Foundation
import Observation

/// A running countdown for one step. `id` is the step's own id, so a step can only have one
/// timer at a time — starting it again while already running just restarts the countdown.
public struct ActiveTimer: Identifiable, Hashable, Sendable {
    public let step: RecipeStep
    public let totalSeconds: Int
    public var remainingSeconds: Int
    public var id: UUID { step.id }
}

/// Drives the step-through experience for one cooking session. Works identically for solo
/// recipes (`role: nil`, `peerSync: nil`) and two-person recipes — local navigation never
/// depends on a connected peer, sync is a strictly additive layer on top.
@Observable
public final class CookingSessionViewModel {
    public let recipe: Recipe
    public let role: StepAssignee?
    public let track: [RecipeStep]
    public private(set) var currentIndex: Int = 0

    private let peerSync: PeerSyncService?

    // MARK: - Timers (stack — more than one can run at once)

    /// Timers *I* started, keyed by step. Live independently of `currentIndex`, so starting a
    /// timer on one step and moving to another keeps it counting down in the background.
    public private(set) var activeTimers: [ActiveTimer] = []
    /// A mirror of the partner's running timers, kept in sync by `timerStarted`/`timerCancelled`
    /// messages and then ticked locally (so it's not sending a message every second).
    public private(set) var partnerActiveTimers: [ActiveTimer] = []
    /// Fires once per step, when a countdown *I* started reaches zero.
    public var onTimerFinished: ((RecipeStep) -> Void)?
    /// Fires when *I* start a timer, with its duration — the app layer uses this to schedule a
    /// local notification, so the timer still reaches you if the phone is locked or you've
    /// switched apps by the time it finishes.
    public var onTimerScheduled: ((RecipeStep, Int) -> Void)?
    /// Fires when a timer *I* started is cancelled before finishing — the app layer uses this to
    /// cancel the corresponding pending notification. (Natural completion is `onTimerFinished`,
    /// not this — the app layer cancels the pending notification there too, since it's redundant
    /// once you've already seen the in-app alert.)
    public var onTimerUnscheduled: ((RecipeStep) -> Void)?

    private var ticker: Timer?

    /// Fires whenever `currentIndex` or `activeTimers` changes — the app layer (`ActiveSessionStore`)
    /// uses this to keep an on-disk snapshot of solo sessions up to date, so a force-quit mid-recipe
    /// doesn't lose all progress. Not fired for `partnerActiveTimers` changes — nothing about the
    /// partner's state is ever persisted (see `ActiveSessionStore`'s doc comment on why two-person
    /// sessions aren't snapshotted at all).
    public var onMutated: (() -> Void)?

    // MARK: - Partner session lifecycle

    /// True once the partner has explicitly ended the session (as opposed to just dropping out
    /// of range, which triggers `PeerSyncService`'s own auto-reconnect instead).
    public private(set) var partnerDidLeave = false

    public init(recipe: Recipe, role: StepAssignee? = nil, peerSync: PeerSyncService? = nil) {
        self.recipe = recipe
        self.role = role
        self.track = recipe.track(for: role)
        self.peerSync = peerSync

        peerSync?.onPartnerTimerStarted = { [weak self] stepIndex, duration in
            self?.handlePartnerTimerStarted(stepIndex: stepIndex, duration: duration)
        }
        peerSync?.onPartnerTimerCancelled = { [weak self] stepIndex in
            self?.handlePartnerTimerCancelled(stepIndex: stepIndex)
        }
        peerSync?.onPartnerLeft = { [weak self] in
            self?.partnerDidLeave = true
        }
        peerSync?.onConnected = { [weak self] in
            self?.announceProgressAndTimers()
        }
    }

    deinit {
        ticker?.invalidate()
    }

    public var currentStep: RecipeStep? {
        guard currentIndex >= 0, currentIndex < track.count else { return nil }
        return track[currentIndex]
    }

    /// True once the user has tapped past the final step.
    public var isComplete: Bool {
        currentIndex >= track.count
    }

    public var isLastStep: Bool {
        currentIndex == track.count - 1
    }

    public var progressText: String {
        "Step \(min(currentIndex + 1, track.count)) of \(track.count)"
    }

    public var progressFraction: Double {
        guard !track.isEmpty else { return 0 }
        return Double(min(currentIndex, track.count)) / Double(track.count)
    }

    /// Advances to the next step. On the final step this completes the recipe — callers that
    /// want to require deliberate confirmation before finishing (e.g. a hold-to-confirm gesture)
    /// should guard `isLastStep` themselves before calling this; the view model doesn't enforce
    /// any particular confirmation UI.
    public func advance() {
        guard currentIndex < track.count else { return }
        currentIndex += 1
        peerSync?.sendProgress(stepIndex: currentIndex)
        if isComplete {
            // Finishing the recipe (including via hold-to-finish) shouldn't leave a timer
            // ticking in the background — reuses cancelTimer's existing teardown so the pending
            // local notification is unscheduled too, not just the in-memory countdown.
            for timer in activeTimers {
                cancelTimer(for: timer.step)
            }
        }
        onMutated?()
    }

    public func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        peerSync?.sendProgress(stepIndex: currentIndex)
        onMutated?()
    }

    /// Reconstructs local step/timer state after a relaunch — see `ActiveSessionStore.restoreIfNeeded`,
    /// the only caller. `timers` should already have expired ones (a past `endDate`) filtered out;
    /// this doesn't fire `onTimerFinished` for any of them, since whatever finished while the app was
    /// dead already surfaced its own local notification instead.
    func restoreState(currentIndex: Int, timers: [ActiveTimer]) {
        self.currentIndex = min(max(currentIndex, 0), track.count)
        self.activeTimers = timers
        if !timers.isEmpty {
            ensureTicking()
        }
    }

    /// `nil` for a solo session; otherwise the opposite of `role`.
    private var partnerRole: StepAssignee? {
        switch role {
        case .personA: return .personB
        case .personB: return .personA
        default: return nil
        }
    }

    /// The partner's current step, resolved locally from the recipe's master step list —
    /// only the index travels over the wire.
    public var partnerStep: RecipeStep? {
        guard let peerSync, let partnerIndex = peerSync.partnerStepIndex, let partnerRole else { return nil }
        let partnerTrack = recipe.track(for: partnerRole)
        guard partnerIndex >= 0, partnerIndex < partnerTrack.count else { return nil }
        return partnerTrack[partnerIndex]
    }

    /// The partner's progress through *their* track, as a 0...1 fraction — comparable directly
    /// against `progressFraction` even when the two tracks have different lengths, which is what
    /// lets a "how far ahead is my partner" slider make sense.
    public var partnerProgressFraction: Double? {
        guard let peerSync, let partnerIndex = peerSync.partnerStepIndex, let partnerRole else { return nil }
        let partnerTrack = recipe.track(for: partnerRole)
        guard !partnerTrack.isEmpty else { return nil }
        return Double(min(partnerIndex, partnerTrack.count)) / Double(partnerTrack.count)
    }

    public var partnerConnectionState: ConnectionState {
        peerSync?.connectionState ?? .idle
    }

    /// The partner's chosen display name, once learned — `nil` until the name exchange completes.
    public var partnerName: String? {
        peerSync?.partnerName
    }

    /// True while the partner is still connected but has stepped away from the step screen (e.g.
    /// backed out to the recipe overview) — distinct from `partnerConnectionState == .disconnected`,
    /// which means the connection itself dropped.
    public var partnerIsAway: Bool {
        peerSync?.partnerIsAway ?? false
    }

    /// Tells the partner whether I'm currently looking at the step screen — sent when navigating
    /// away to the recipe overview and when coming back (including via "Resume Cooking"). Purely
    /// informational: it doesn't affect the connection itself, which stays up either way.
    public func announcePresence(isAway: Bool) {
        peerSync?.sendPresenceUpdate(isAway: isAway)
    }

    /// Sends a deliberate end-of-session signal to the partner (if connected) and tears down
    /// the local peer connection with no auto-reconnect attempt. Local step navigation keeps
    /// working afterwards — ending the shared session doesn't stop you from finishing the
    /// recipe on your own.
    public func endSharedSession() {
        peerSync?.leaveSession()
    }

    /// Re-announces my current step and every timer I have running — called whenever the
    /// connection (re)reaches `.connected`. A reconnect otherwise carries no information about
    /// where either side actually is: only `advance()`/`goBack()`/`startTimer()` send anything on
    /// their own, and a reconnect triggers none of those, so without this the partner would look
    /// frozen at whatever they were doing right before the drop.
    private func announceProgressAndTimers() {
        peerSync?.sendProgress(stepIndex: currentIndex)
        for timer in activeTimers {
            guard let index = track.firstIndex(where: { $0.id == timer.step.id }) else { continue }
            // Resend the *remaining* time, not the total — the partner's mirrored countdown
            // should reflect reality, not restart from the full duration.
            peerSync?.sendTimerStarted(stepIndex: index, durationSeconds: timer.remainingSeconds)
        }
    }

    // MARK: - Timers

    public func activeTimer(for step: RecipeStep) -> ActiveTimer? {
        activeTimers.first { $0.step.id == step.id }
    }

    public func startTimer(for step: RecipeStep) {
        guard let duration = step.timerSeconds else { return }
        if let idx = activeTimers.firstIndex(where: { $0.step.id == step.id }) {
            activeTimers[idx].remainingSeconds = duration
        } else {
            activeTimers.append(ActiveTimer(step: step, totalSeconds: duration, remainingSeconds: duration))
        }
        ensureTicking()
        if let index = track.firstIndex(where: { $0.id == step.id }) {
            peerSync?.sendTimerStarted(stepIndex: index, durationSeconds: duration)
        }
        onTimerScheduled?(step, duration)
        onMutated?()
    }

    public func cancelTimer(for step: RecipeStep) {
        guard activeTimers.contains(where: { $0.step.id == step.id }) else { return }
        activeTimers.removeAll { $0.step.id == step.id }
        if let index = track.firstIndex(where: { $0.id == step.id }) {
            peerSync?.sendTimerCancelled(stepIndex: index)
        }
        stopTickingIfIdle()
        onTimerUnscheduled?(step)
        onMutated?()
    }

    private func handlePartnerTimerStarted(stepIndex: Int, duration: Int) {
        guard let partnerRole else { return }
        let partnerTrack = recipe.track(for: partnerRole)
        guard stepIndex >= 0, stepIndex < partnerTrack.count else { return }
        let step = partnerTrack[stepIndex]
        if let idx = partnerActiveTimers.firstIndex(where: { $0.step.id == step.id }) {
            partnerActiveTimers[idx].remainingSeconds = duration
        } else {
            partnerActiveTimers.append(ActiveTimer(step: step, totalSeconds: duration, remainingSeconds: duration))
        }
        ensureTicking()
    }

    private func handlePartnerTimerCancelled(stepIndex: Int) {
        guard let partnerRole else { return }
        let partnerTrack = recipe.track(for: partnerRole)
        guard stepIndex >= 0, stepIndex < partnerTrack.count else { return }
        let stepID = partnerTrack[stepIndex].id
        partnerActiveTimers.removeAll { $0.step.id == stepID }
        stopTickingIfIdle()
    }

    private func ensureTicking() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTickingIfIdle() {
        guard activeTimers.isEmpty, partnerActiveTimers.isEmpty else { return }
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        var finished: [RecipeStep] = []
        for i in activeTimers.indices.reversed() {
            guard activeTimers[i].remainingSeconds > 0 else { continue }
            activeTimers[i].remainingSeconds -= 1
            if activeTimers[i].remainingSeconds == 0 {
                let step = activeTimers[i].step
                finished.append(step)
                activeTimers.remove(at: i)
                if let index = track.firstIndex(where: { $0.id == step.id }) {
                    peerSync?.sendTimerCancelled(stepIndex: index) // let the partner know it's done too
                }
            }
        }
        for i in partnerActiveTimers.indices.reversed() {
            guard partnerActiveTimers[i].remainingSeconds > 0 else { continue }
            partnerActiveTimers[i].remainingSeconds -= 1
            if partnerActiveTimers[i].remainingSeconds == 0 {
                partnerActiveTimers.remove(at: i)
            }
        }
        for step in finished {
            onTimerFinished?(step)
        }
        if !finished.isEmpty {
            onMutated?()
        }
        stopTickingIfIdle()
    }
}

// MARK: - Hashable (identity-based, for use as SwiftUI navigation-path elements)

extension CookingSessionViewModel: Hashable {
    public static func == (lhs: CookingSessionViewModel, rhs: CookingSessionViewModel) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
