import Foundation

public enum SyncMessageType: String, Codable, Sendable {
    case recipeSync
    case progressUpdate
}

/// Wire protocol sent between peers over MultipeerConnectivity.
/// Carries indices only, never instruction text — both devices ship identical
/// bundled recipe data and resolve display text locally.
public struct SyncMessage: Codable, Equatable, Sendable {
    public let type: SyncMessageType
    public let recipeID: UUID?
    public let stepIndex: Int?

    public init(type: SyncMessageType, recipeID: UUID? = nil, stepIndex: Int? = nil) {
        self.type = type
        self.recipeID = recipeID
        self.stepIndex = stepIndex
    }

    public static func recipeSync(recipeID: UUID) -> SyncMessage {
        SyncMessage(type: .recipeSync, recipeID: recipeID)
    }

    public static func progressUpdate(stepIndex: Int) -> SyncMessage {
        SyncMessage(type: .progressUpdate, stepIndex: stepIndex)
    }
}
