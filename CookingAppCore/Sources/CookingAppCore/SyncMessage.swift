import Foundation

public enum SyncMessageType: String, Codable, Sendable {
    case recipeSync
    case progressUpdate
    case timerStarted
    case timerCancelled
    case leaveSession
}

/// Wire protocol sent between peers over MultipeerConnectivity.
/// Carries indices only, never instruction text — both devices ship identical
/// bundled recipe data and resolve display text locally.
public struct SyncMessage: Codable, Equatable, Sendable {
    public let type: SyncMessageType
    public let recipeID: UUID?
    public let stepIndex: Int?
    /// `.timerStarted` only — the timer's total duration, so the receiver can mirror the
    /// countdown locally instead of needing a message every second.
    public let timerDurationSeconds: Int?

    public init(type: SyncMessageType, recipeID: UUID? = nil, stepIndex: Int? = nil, timerDurationSeconds: Int? = nil) {
        self.type = type
        self.recipeID = recipeID
        self.stepIndex = stepIndex
        self.timerDurationSeconds = timerDurationSeconds
    }

    public static func recipeSync(recipeID: UUID) -> SyncMessage {
        SyncMessage(type: .recipeSync, recipeID: recipeID)
    }

    public static func progressUpdate(stepIndex: Int) -> SyncMessage {
        SyncMessage(type: .progressUpdate, stepIndex: stepIndex)
    }

    /// `stepIndex` is an index into the *sender's own* track — the receiver resolves it against
    /// a track built for the sender's role, the same pattern `progressUpdate` already uses.
    public static func timerStarted(stepIndex: Int, durationSeconds: Int) -> SyncMessage {
        SyncMessage(type: .timerStarted, stepIndex: stepIndex, timerDurationSeconds: durationSeconds)
    }

    public static func timerCancelled(stepIndex: Int) -> SyncMessage {
        SyncMessage(type: .timerCancelled, stepIndex: stepIndex)
    }

    public static func leaveSession() -> SyncMessage {
        SyncMessage(type: .leaveSession)
    }
}
