import Foundation

public enum StepAssignee: String, Codable, Sendable {
    case solo
    case shared
    case personA
    case personB
}

public struct RecipeStep: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let order: Int
    public let instruction: String
    public let assignee: StepAssignee
    /// Drives the live countdown in StepTimerControl — nil means the step has no timer at all.
    public let timerSeconds: Int?
    /// SF Symbol name shown as this step's illustration.
    public let imageSystemName: String

    public init(id: UUID = UUID(), order: Int, instruction: String, assignee: StepAssignee, timerSeconds: Int? = nil, imageSystemName: String) {
        self.id = id
        self.order = order
        self.instruction = instruction
        self.assignee = assignee
        self.timerSeconds = timerSeconds
        self.imageSystemName = imageSystemName
    }
}

/// A dietary restriction a recipe is compatible with. Icons are decorative — the text label is
/// the primary signal — since a couple of these SF Symbol names couldn't be visually verified
/// without Xcode in the environment this was built in; spot-check them in Xcode's SF Symbols
/// picker if any render blank.
public enum DietaryTag: String, Codable, CaseIterable, Hashable, Sendable {
    case vegetarian
    case vegan
    case glutenFree
    case lactoseFree
    case nutFree

    public var label: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .glutenFree: return "Gluten-Free"
        case .lactoseFree: return "Lactose-Free"
        case .nutFree: return "Nut-Free"
        }
    }

    public var systemImage: String {
        switch self {
        case .vegetarian: return "leaf.fill"
        case .vegan: return "leaf.circle.fill"
        case .glutenFree: return "circle.slash"
        case .lactoseFree: return "nosign"
        case .nutFree: return "exclamationmark.octagon"
        }
    }
}

public struct Ingredient: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let amount: String

    public init(id: UUID = UUID(), name: String, amount: String) {
        self.id = id
        self.name = name
        self.amount = amount
    }
}

public struct Recipe: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let summary: String
    public let servings: Int?
    /// Master ordered list across every assignee; per-person tracks are derived from this.
    public let steps: [RecipeStep]
    /// SF Symbol shown as this recipe's "photo" on the list/overview screens.
    public let iconSystemName: String
    /// 1...3, rendered as filled-out-of-3 stars.
    public let difficulty: Int
    /// 0...3, rendered as filled-out-of-3 flames. 0 means not spicy at all.
    public let spiceLevel: Int
    public let cookTimeMinutes: Int
    public let dietaryTags: [DietaryTag]
    public let ingredients: [Ingredient]

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        servings: Int? = nil,
        steps: [RecipeStep],
        iconSystemName: String,
        difficulty: Int,
        spiceLevel: Int = 0,
        cookTimeMinutes: Int,
        dietaryTags: [DietaryTag] = [],
        ingredients: [Ingredient]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.servings = servings
        self.steps = steps
        self.iconSystemName = iconSystemName
        self.difficulty = difficulty
        self.spiceLevel = spiceLevel
        self.cookTimeMinutes = cookTimeMinutes
        self.dietaryTags = dietaryTags
        self.ingredients = ingredients
    }

    /// True when this recipe has an actual hand-curated Person A / Person B task split.
    /// Two-person mode is still available on recipes where this is false (see `track(for:)`) —
    /// it just falls back to mirroring the same full step list to both phones, rather than
    /// dividing labor, since there's no sensible split to offer.
    public var hasCuratedSplit: Bool {
        steps.contains { $0.assignee == .personA || $0.assignee == .personB }
    }

    /// The ordered list of steps visible to a given role.
    ///
    /// - `role: nil` — solo mode: the full step list, in order.
    /// - `role: .personA` / `.personB` on a recipe with a curated split — that person's own
    ///   steps plus every `.shared` step.
    /// - `role: .personA` / `.personB` on a recipe **without** a curated split — the full step
    ///   list, same as solo. This is the "mirror mode" fallback: two people can still cook any
    ///   recipe together, side by side, each following the complete recipe on their own phone,
    ///   even when there's no sensible way to divide its steps into two tracks.
    public func track(for role: StepAssignee?) -> [RecipeStep] {
        guard let role, hasCuratedSplit else {
            return steps.sorted { $0.order < $1.order }
        }
        return steps
            .filter { $0.assignee == .shared || $0.assignee == role }
            .sorted { $0.order < $1.order }
    }
}
