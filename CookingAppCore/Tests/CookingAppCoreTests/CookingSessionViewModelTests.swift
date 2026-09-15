import Foundation
import MultipeerConnectivity
import Testing
@testable import CookingAppCore

/// Covers the parts of `CookingSessionViewModel` that involve a `PeerSyncService` — partner
/// timer mirroring, progress comparison, and the "partner left" signal — by driving a real
/// `PeerSyncService` instance through its synchronous internal handlers (no actual networking)
/// exactly as if messages had arrived from a partner device. See `PeerSyncServiceTests` for why
/// this works without a live MultipeerConnectivity session.
struct CookingSessionViewModelTests {

    @Test func isLastStepIsTrueOnlyOnTheFinalStep() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        let stepCount = session.track.count

        for i in 0..<(stepCount - 1) {
            #expect(!session.isLastStep, "unexpectedly last at index \(i)")
            session.advance()
        }
        #expect(session.isLastStep)
    }

    @Test func partnerProgressFractionIsNilWithoutAPeer() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.pastaForTwo, role: .personA)
        #expect(session.partnerProgressFraction == nil)
    }

    @Test func partnerStepIsNilWithoutAPeer() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.pastaForTwo, role: .personA)
        #expect(session.partnerStep == nil)
    }

    @Test func partnerStepIsNilForASoloSession() {
        // No peer *and* no role — the common solo case — should behave the same as the
        // no-peer-connected two-person case above, not crash on a nil `partnerRole`.
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        #expect(session.partnerStep == nil)
        #expect(session.partnerProgressFraction == nil)
    }

    @Test func partnerStepResolvesAgainstThePartnersOwnTrackNotMine() {
        let recipe = SampleRecipes.pastaForTwo
        let peerSync = PeerSyncService(displayName: "me")
        // I'm Person A; my partner is Person B.
        let session = CookingSessionViewModel(recipe: recipe, role: .personA, peerSync: peerSync)

        let personBTrack = recipe.track(for: .personB)
        peerSync.handleReceivedMessage(.progressUpdate(stepIndex: 2))

        #expect(session.partnerStep?.id == personBTrack[2].id)
        #expect(session.partnerStep?.assignee != .personA)
    }

    @Test func partnerConnectionStateIsIdleForASoloSessionWithNoPeerSync() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        #expect(session.partnerConnectionState == .idle)
    }

    @Test func partnerNameIsNilUntilLearnedThenReflectsThePeerSyncService() {
        let peerSync = PeerSyncService(displayName: "me")
        let session = CookingSessionViewModel(recipe: SampleRecipes.pastaForTwo, role: .personA, peerSync: peerSync)
        #expect(session.partnerName == nil)

        peerSync.handleReceivedMessage(.introduce(name: "Sam"))

        #expect(session.partnerName == "Sam")
    }

    @Test func partnerNameIsNilForASoloSessionWithNoPeerSync() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        #expect(session.partnerName == nil)
    }

    @Test func partnerIsAwayReflectsPresenceUpdatesFromThePeerSyncService() {
        let peerSync = PeerSyncService(displayName: "me")
        let session = CookingSessionViewModel(recipe: SampleRecipes.pastaForTwo, role: .personA, peerSync: peerSync)
        #expect(!session.partnerIsAway)

        peerSync.handleReceivedMessage(.presenceUpdate(isAway: true))
        #expect(session.partnerIsAway)

        peerSync.handleReceivedMessage(.presenceUpdate(isAway: false))
        #expect(!session.partnerIsAway)
    }

    @Test func partnerIsAwayIsFalseForASoloSessionWithNoPeerSync() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        #expect(!session.partnerIsAway)
    }

    @Test func initWiresOnConnectedForReconnectResync() {
        // `announceProgressAndTimers()` itself can't be observed end-to-end here — `send()` is a
        // no-op without a real connected MCSession peer (the same limitation every other outgoing
        // send in this suite has) — but we *can* confirm the hook that triggers it is actually
        // wired up, which is what makes a real reconnect (in the running app) re-announce
        // progress instead of leaving the partner's view stale.
        let peerSync = PeerSyncService(displayName: "me")
        _ = CookingSessionViewModel(recipe: SampleRecipes.pastaForTwo, role: .personA, peerSync: peerSync)

        #expect(peerSync.onConnected != nil)
    }

    @Test func partnerConnectionStateReflectsThePeerSyncServiceOnceConnected() {
        let peer = MCPeerID(displayName: "partner-device")
        let peerSync = PeerSyncService(displayName: "me")
        peerSync.startBrowsing() // role must be set before .connected is legitimate
        let session = CookingSessionViewModel(recipe: SampleRecipes.pastaForTwo, role: .personA, peerSync: peerSync)

        peerSync.handleSessionStateChange(.connected, peerID: peer)

        #expect(session.partnerConnectionState == .connected)
    }

    @Test func partnerProgressFractionReflectsPartnersOwnTrackLength() {
        let recipe = SampleRecipes.pastaForTwo
        let peerSync = PeerSyncService(displayName: "me")
        let session = CookingSessionViewModel(recipe: recipe, role: .personA, peerSync: peerSync)

        let personBTrackCount = recipe.track(for: .personB).count
        peerSync.handleReceivedMessage(.progressUpdate(stepIndex: personBTrackCount)) // partner just finished

        #expect(session.partnerProgressFraction == 1.0)
    }

    @Test func partnerTimerStartedMessageAddsAMirroredTimerResolvedAgainstPartnersTrack() {
        let recipe = SampleRecipes.pastaForTwo
        let peerSync = PeerSyncService(displayName: "me")
        // I'm Person A; my partner is Person B.
        let session = CookingSessionViewModel(recipe: recipe, role: .personA, peerSync: peerSync)

        let personBTrack = recipe.track(for: .personB)
        let partnerTimedIndex = personBTrack.firstIndex { $0.timerSeconds != nil }!
        let partnerTimedStep = personBTrack[partnerTimedIndex]

        peerSync.handleReceivedMessage(.timerStarted(stepIndex: partnerTimedIndex, durationSeconds: 600))

        #expect(session.partnerActiveTimers.count == 1)
        #expect(session.partnerActiveTimers.first?.step.id == partnerTimedStep.id)
        #expect(session.partnerActiveTimers.first?.remainingSeconds == 600)
    }

    @Test func partnerTimerCancelledMessageRemovesTheMirroredTimer() {
        let recipe = SampleRecipes.pastaForTwo
        let peerSync = PeerSyncService(displayName: "me")
        let session = CookingSessionViewModel(recipe: recipe, role: .personA, peerSync: peerSync)

        let personBTrack = recipe.track(for: .personB)
        let partnerTimedIndex = personBTrack.firstIndex { $0.timerSeconds != nil }!

        peerSync.handleReceivedMessage(.timerStarted(stepIndex: partnerTimedIndex, durationSeconds: 600))
        #expect(session.partnerActiveTimers.count == 1)

        peerSync.handleReceivedMessage(.timerCancelled(stepIndex: partnerTimedIndex))
        #expect(session.partnerActiveTimers.isEmpty)
    }

    @Test func myTimersAndPartnerTimersAreIndependentStacks() {
        let recipe = SampleRecipes.pastaForTwo
        let peerSync = PeerSyncService(displayName: "me")
        let session = CookingSessionViewModel(recipe: recipe, role: .personA, peerSync: peerSync)

        let myTimedStep = session.track.first { $0.timerSeconds != nil }!
        session.startTimer(for: myTimedStep)

        let personBTrack = recipe.track(for: .personB)
        let partnerTimedIndex = personBTrack.firstIndex { $0.timerSeconds != nil }!
        peerSync.handleReceivedMessage(.timerStarted(stepIndex: partnerTimedIndex, durationSeconds: 600))

        #expect(session.activeTimers.count == 1)
        #expect(session.partnerActiveTimers.count == 1)

        session.cancelTimer(for: myTimedStep)
        #expect(session.activeTimers.isEmpty)
        #expect(session.partnerActiveTimers.count == 1) // untouched by cancelling my own
    }

    // MARK: - Notification scheduling hooks

    @Test func startingATimerFiresOnTimerScheduledWithItsDuration() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.searedSteak)
        let step = session.track.first { $0.timerSeconds == 180 }!

        var scheduled: (RecipeStep, Int)?
        session.onTimerScheduled = { scheduled = ($0, $1) }

        session.startTimer(for: step)

        #expect(scheduled?.0.id == step.id)
        #expect(scheduled?.1 == 180)
    }

    @Test func cancellingATimerFiresOnTimerUnscheduled() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.searedSteak)
        let step = session.track.first { $0.timerSeconds == 180 }!
        session.startTimer(for: step)

        var unscheduledStep: RecipeStep?
        session.onTimerUnscheduled = { unscheduledStep = $0 }
        session.cancelTimer(for: step)

        #expect(unscheduledStep?.id == step.id)
    }

    @Test func cancellingATimerThatIsntRunningDoesNotFireOnTimerUnscheduled() {
        let recipe = SampleRecipes.searedSteak
        let session = CookingSessionViewModel(recipe: recipe)
        let neverStartedStep = recipe.soloSteps.first { $0.timerSeconds == 180 }!

        var fired = false
        session.onTimerUnscheduled = { _ in fired = true }
        session.cancelTimer(for: neverStartedStep)

        #expect(!fired)
    }

    @Test func partnerLeavingSessionSetsPartnerDidLeave() {
        let peerSync = PeerSyncService(displayName: "me")
        let session = CookingSessionViewModel(recipe: SampleRecipes.pastaForTwo, role: .personB, peerSync: peerSync)
        #expect(!session.partnerDidLeave)

        // Simulates a `leaveSession` message arriving from the partner (Person A) — not my own
        // `endSharedSession()`, which only ends things from my side and shouldn't flip this flag.
        peerSync.handleReceivedMessage(.leaveSession())

        #expect(session.partnerDidLeave)
    }

    @Test func endingMyOwnSessionDoesNotSetPartnerDidLeave() {
        let session = CookingSessionViewModel(
            recipe: SampleRecipes.pastaForTwo,
            role: .personA,
            peerSync: PeerSyncService(displayName: "me")
        )

        session.endSharedSession()

        #expect(!session.partnerDidLeave)
    }

    @Test func endSharedSessionDoesNotPreventContinuingSoloNavigation() {
        // Ending the shared session is a peer-connection concern only — local step navigation
        // must keep working afterward, same as it does for a plain solo recipe.
        let session = CookingSessionViewModel(
            recipe: SampleRecipes.pastaForTwo,
            role: .personA,
            peerSync: PeerSyncService(displayName: "me")
        )
        let startIndex = session.currentIndex

        session.endSharedSession()
        session.advance()

        #expect(session.currentIndex == startIndex + 1)
    }

    @Test func announcePresenceDoesNotCrashForATwoPersonSessionOrASoloOne() {
        // Same "can't observe the actual send" limitation as the reconnect-resync test above —
        // this just confirms the call is safe/harmless in both configurations.
        let twoPerson = CookingSessionViewModel(
            recipe: SampleRecipes.pastaForTwo,
            role: .personA,
            peerSync: PeerSyncService(displayName: "me")
        )
        twoPerson.announcePresence(isAway: true)
        twoPerson.announcePresence(isAway: false)

        let solo = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        solo.announcePresence(isAway: true) // peerSync is nil — must be a no-op, not a crash
    }

    // MARK: - Finishing cancels any still-running timer

    @Test func advancingPastTheLastStepCancelsEveryRunningTimerAndUnschedulesItsNotification() {
        let recipe = SampleRecipes.searedSteak
        let session = CookingSessionViewModel(recipe: recipe)
        let timedStep = recipe.soloSteps.first { $0.timerSeconds == 180 }!
        session.startTimer(for: timedStep)
        #expect(session.activeTimers.count == 1)

        var unscheduledSteps: [RecipeStep] = []
        session.onTimerUnscheduled = { unscheduledSteps.append($0) }

        for _ in 0..<session.track.count {
            session.advance()
        }

        #expect(session.isComplete)
        #expect(session.activeTimers.isEmpty)
        #expect(unscheduledSteps.map(\.id) == [timedStep.id])
    }

    @Test func advancingPastTheLastStepWithMultipleRunningTimersCancelsAllOfThem() {
        let recipe = SampleRecipes.grilledCheese
        let session = CookingSessionViewModel(recipe: recipe)
        let timedSteps = session.track.filter { $0.timerSeconds != nil }
        #expect(timedSteps.count >= 2, "test needs a track with at least two timed steps")
        for step in timedSteps {
            session.startTimer(for: step)
        }
        #expect(session.activeTimers.count == timedSteps.count)

        for _ in 0..<session.track.count {
            session.advance()
        }

        #expect(session.isComplete)
        #expect(session.activeTimers.isEmpty)
    }

    @Test func advancingWithoutReachingTheEndLeavesRunningTimersAlone() {
        let recipe = SampleRecipes.searedSteak
        let session = CookingSessionViewModel(recipe: recipe)
        let timedStep = recipe.soloSteps.first { $0.timerSeconds == 1800 }! // the very first step
        session.startTimer(for: timedStep)

        session.advance() // one step forward, nowhere near complete

        #expect(!session.isComplete)
        #expect(session.activeTimers.count == 1)
        session.cancelTimer(for: timedStep) // avoid leaking a live Timer past the end of the test
    }

    // MARK: - ActiveSessionStore

    @Test func activeSessionStoreStartsEmpty() {
        let store = ActiveSessionStore()
        #expect(!store.hasActiveSession)
        #expect(store.currentSession == nil)
    }

    @Test func activeSessionStoreHoldsTheSameInstanceAcrossSetAndGet() {
        let store = ActiveSessionStore()
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        session.advance() // give it distinguishing state

        store.setActive(session)

        #expect(store.hasActiveSession)
        #expect(store.currentSession === session)
        #expect(store.currentSession?.currentIndex == 1)
    }

    @Test func activeSessionStoreClearRemovesTheSession() {
        let store = ActiveSessionStore()
        store.setActive(CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs))

        store.clear()

        #expect(!store.hasActiveSession)
        #expect(store.currentSession == nil)
    }
}
