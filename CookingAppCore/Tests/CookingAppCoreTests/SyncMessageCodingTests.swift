import Foundation
import Testing
@testable import CookingAppCore

struct SyncMessageCodingTests {

    @Test func recipeSyncRoundTripsThroughJSON() throws {
        let recipeID = UUID()
        let original = SyncMessage.recipeSync(recipeID: recipeID, hostRole: .personA, senderName: "Alex")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)

        #expect(decoded == original)
        #expect(decoded.type == .recipeSync)
        #expect(decoded.recipeID == recipeID)
        #expect(decoded.hostRole == .personA)
        #expect(decoded.senderName == "Alex")
        #expect(decoded.stepIndex == nil)
    }

    @Test func introduceRoundTripsThroughJSON() throws {
        let original = SyncMessage.introduce(name: "Sam")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)

        #expect(decoded == original)
        #expect(decoded.type == .introduce)
        #expect(decoded.senderName == "Sam")
        #expect(decoded.recipeID == nil)
        #expect(decoded.hostRole == nil)
    }

    @Test func presenceUpdateRoundTripsThroughJSONForBothAwayAndReturned() throws {
        for isAway in [true, false] {
            let original = SyncMessage.presenceUpdate(isAway: isAway)

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)

            #expect(decoded == original)
            #expect(decoded.type == .presenceUpdate)
            #expect(decoded.isAway == isAway)
        }
    }

    @Test func progressUpdateRoundTripsThroughJSON() throws {
        let original = SyncMessage.progressUpdate(stepIndex: 4)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)

        #expect(decoded == original)
        #expect(decoded.type == .progressUpdate)
        #expect(decoded.stepIndex == 4)
        #expect(decoded.recipeID == nil)
    }

    @Test func progressUpdateAtZeroRoundTrips() throws {
        // Regression guard: stepIndex 0 must not be dropped/confused with a missing optional.
        let original = SyncMessage.progressUpdate(stepIndex: 0)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)

        #expect(decoded.stepIndex == 0)
    }

    @Test func bothOptionalFieldsNilRoundTrips() throws {
        let original = SyncMessage(type: .progressUpdate)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)

        #expect(decoded == original)
        #expect(decoded.recipeID == nil)
        #expect(decoded.stepIndex == nil)
    }

    @Test func timerStartedRoundTripsThroughJSON() throws {
        let original = SyncMessage.timerStarted(stepIndex: 3, durationSeconds: 600)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)

        #expect(decoded == original)
        #expect(decoded.type == .timerStarted)
        #expect(decoded.stepIndex == 3)
        #expect(decoded.timerDurationSeconds == 600)
        #expect(decoded.recipeID == nil)
    }

    @Test func timerCancelledRoundTripsThroughJSON() throws {
        let original = SyncMessage.timerCancelled(stepIndex: 3)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)

        #expect(decoded == original)
        #expect(decoded.type == .timerCancelled)
        #expect(decoded.stepIndex == 3)
        #expect(decoded.timerDurationSeconds == nil)
    }

    @Test func leaveSessionRoundTripsThroughJSON() throws {
        let original = SyncMessage.leaveSession()

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)

        #expect(decoded == original)
        #expect(decoded.type == .leaveSession)
        #expect(decoded.recipeID == nil)
        #expect(decoded.stepIndex == nil)
        #expect(decoded.timerDurationSeconds == nil)
    }

    @Test func decodingMalformedDataThrowsRatherThanCrashingOrSilentlyDefaulting() {
        // `PeerSyncService.session(_:didReceive:fromPeer:)` relies on this throwing (it uses
        // `try?` and just drops the message) rather than trapping — a stray/corrupt packet from
        // a misbehaving peer must never crash the receiving app.
        let garbage = Data([0xFF, 0x00, 0x13, 0x37])
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SyncMessage.self, from: garbage)
        }
    }

    @Test func decodingAnUnknownMessageTypeThrows() {
        // Forward-compatibility guard: a message with a `type` string this build doesn't know
        // about must fail to decode, not decode into some undefined/default case.
        let json = #"{"type":"someFutureMessageType","recipeID":null,"stepIndex":null,"timerDurationSeconds":null}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SyncMessage.self, from: Data(json.utf8))
        }
    }
}
