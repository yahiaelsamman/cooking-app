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
