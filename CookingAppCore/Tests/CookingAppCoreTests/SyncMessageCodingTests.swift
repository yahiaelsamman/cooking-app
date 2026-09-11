import Foundation
import Testing
@testable import CookingAppCore

struct SyncMessageCodingTests {

    @Test func recipeSyncRoundTripsThroughJSON() throws {
        let recipeID = UUID()
        let original = SyncMessage.recipeSync(recipeID: recipeID)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)

        #expect(decoded == original)
        #expect(decoded.type == .recipeSync)
        #expect(decoded.recipeID == recipeID)
        #expect(decoded.stepIndex == nil)
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
}
