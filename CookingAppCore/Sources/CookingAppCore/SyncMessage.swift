import Foundation

public enum SyncMessageType: String, Codable, Sendable {
    case recipeSync
    /// Sent by the joiner right after accepting a `recipeSync`, so the host learns the joiner's
    /// chosen name too (`recipeSync` only carries the *host's* name, since it's the only message
    /// the host doesn't have to wait on).
    case introduce
    case progressUpdate
    case timerStarted
    case timerCancelled
    /// "Stepped away" / "returned" while the underlying connection stays up — distinct from a
    /// real drop, which `ConnectionState`/`ConnectionState.disconnected` already covers.
    case presenceUpdate
    case leaveSession
}

/// Wire protocol sent between peers over MultipeerConnectivity.
/// Carries only indices/ids/names, never step instruction text — both devices ship identical
/// bundled recipe data and resolve display text locally.
public struct SyncMessage: Codable, Equatable, Sendable {
    public let type: SyncMessageType
    public let recipeID: UUID?
    public let stepIndex: Int?
    /// `.timerStarted` only — the timer's total duration, so the receiver can mirror the
    /// countdown locally instead of needing a message every second.
    public let timerDurationSeconds: Int?
    /// `.recipeSync` only — the role the HOST chose for themselves (via the host-side toggle);
    /// the joiner resolves its own role as the opposite of this.
    public let hostRole: StepAssignee?
    /// `.recipeSync` (host → joiner) and `.introduce` (joiner → host) — the sender's chosen name.
    public let senderName: String?
    /// `.presenceUpdate` only.
    public let isAway: Bool?

    public init(
        type: SyncMessageType,
        recipeID: UUID? = nil,
        stepIndex: Int? = nil,
        timerDurationSeconds: Int? = nil,
        hostRole: StepAssignee? = nil,
        senderName: String? = nil,
        isAway: Bool? = nil
    ) {
        self.type = type
        self.recipeID = recipeID
        self.stepIndex = stepIndex
        self.timerDurationSeconds = timerDurationSeconds
        self.hostRole = hostRole
        self.senderName = senderName
        self.isAway = isAway
    }

    public static func recipeSync(recipeID: UUID, hostRole: StepAssignee, senderName: String) -> SyncMessage {
        SyncMessage(type: .recipeSync, recipeID: recipeID, hostRole: hostRole, senderName: senderName)
    }

    public static func introduce(name: String) -> SyncMessage {
        SyncMessage(type: .introduce, senderName: name)
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

    public static func presenceUpdate(isAway: Bool) -> SyncMessage {
        SyncMessage(type: .presenceUpdate, isAway: isAway)
    }

    public static func leaveSession() -> SyncMessage {
        SyncMessage(type: .leaveSession)
    }
}
