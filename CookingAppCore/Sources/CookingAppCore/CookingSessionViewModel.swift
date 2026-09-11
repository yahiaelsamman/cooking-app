import Foundation
import Observation

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

    // MARK: - Timer

    /// The step a running countdown belongs to, if any. Lives independently of `currentIndex`
    /// so a timer started on one step keeps running while you navigate to other steps.
    public private(set) var runningTimerStepID: UUID?
    public private(set) var timerRemainingSeconds: Int = 0
    /// Fires once, off the main run loop's Timer, when a countdown reaches zero.
    public var onTimerFinished: ((RecipeStep) -> Void)?

    private var timer: Timer?

    public init(recipe: Recipe, role: StepAssignee? = nil, peerSync: PeerSyncService? = nil) {
        self.recipe = recipe
        self.role = role
        self.track = recipe.track(for: role)
        self.peerSync = peerSync
    }

    deinit {
        timer?.invalidate()
    }

    public var currentStep: RecipeStep? {
        guard currentIndex >= 0, currentIndex < track.count else { return nil }
        return track[currentIndex]
    }

    /// True once the user has tapped past the final step.
    public var isComplete: Bool {
        currentIndex >= track.count
    }

    public var progressText: String {
        "Step \(min(currentIndex + 1, track.count)) of \(track.count)"
    }

    public var progressFraction: Double {
        guard !track.isEmpty else { return 0 }
        return Double(min(currentIndex, track.count)) / Double(track.count)
    }

    public func advance() {
        guard currentIndex < track.count else { return }
        currentIndex += 1
        peerSync?.sendProgress(stepIndex: currentIndex)
    }

    public func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        peerSync?.sendProgress(stepIndex: currentIndex)
    }

    /// The partner's current step, resolved locally from the recipe's master step list —
    /// only the index travels over the wire.
    public var partnerStep: RecipeStep? {
        guard let peerSync, let partnerIndex = peerSync.partnerStepIndex else { return nil }
        let partnerRole: StepAssignee? = role == .personA ? .personB : (role == .personB ? .personA : nil)
        let partnerTrack = recipe.track(for: partnerRole)
        guard partnerIndex >= 0, partnerIndex < partnerTrack.count else { return nil }
        return partnerTrack[partnerIndex]
    }

    public var partnerConnectionState: ConnectionState {
        peerSync?.connectionState ?? .idle
    }

    /// The step whose timer is currently running, resolved from the local track — `nil` once
    /// the timer finishes or is cancelled.
    public var runningTimerStep: RecipeStep? {
        guard let runningTimerStepID else { return nil }
        return track.first { $0.id == runningTimerStepID }
    }

    public func startTimer(for step: RecipeStep) {
        guard let duration = step.timerSeconds else { return }
        timer?.invalidate()
        runningTimerStepID = step.id
        timerRemainingSeconds = duration
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    public func cancelTimer() {
        timer?.invalidate()
        timer = nil
        runningTimerStepID = nil
        timerRemainingSeconds = 0
    }

    private func tick() {
        guard timerRemainingSeconds > 0 else {
            finishTimer()
            return
        }
        timerRemainingSeconds -= 1
        if timerRemainingSeconds == 0 {
            finishTimer()
        }
    }

    private func finishTimer() {
        timer?.invalidate()
        timer = nil
        let finishedStep = runningTimerStep
        runningTimerStepID = nil
        if let finishedStep {
            onTimerFinished?(finishedStep)
        }
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
