import Foundation
import Testing
@testable import CookingAppCore

@MainActor
struct SessionFlagsTests {

    @Test func acknowledgingPartnerLeftClearsTheFlagSoCookingCanContinue() {
        let peerSync = PeerSyncService(displayName: "me")
        let session = CookingSessionViewModel(recipe: SampleRecipes.pastaForTwo, role: .personB, peerSync: peerSync)

        peerSync.handleReceivedMessage(.leaveSession())
        #expect(session.partnerDidLeave)

        session.acknowledgePartnerLeft()
        #expect(!session.partnerDidLeave)
        session.advance() // still fully usable on their own
        #expect(session.currentIndex == 1)
    }

    @Test func completionIsNotCountedUntilTheViewMarksIt() {
        let session = CookingSessionViewModel(recipe: SampleRecipes.scrambledEggs)
        #expect(!session.completionCounted)
    }
}
