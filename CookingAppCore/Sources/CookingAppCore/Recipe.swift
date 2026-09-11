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
    case dairyFree
    case nutFree

    public var label: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .glutenFree: return "Gluten-Free"
        case .dairyFree: return "Dairy-Free"
        case .nutFree: return "Nut-Free"
        }
    }

    public var systemImage: String {
        switch self {
        case .vegetarian: return "leaf.fill"
        case .vegan: return "leaf.circle.fill"
        case .glutenFree: return "circle.slash"
        case .dairyFree: return "nosign"
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
    public let isTwoPerson: Bool
    /// Master ordered list across every assignee; per-person tracks are derived from this.
    public let steps: [RecipeStep]
    /// SF Symbol shown as this recipe's "photo" on the list/overview screens.
    public let iconSystemName: String
    /// 1...3, rendered as filled-out-of-3 stars.
    public let difficulty: Int
    public let cookTimeMinutes: Int
    public let dietaryTags: [DietaryTag]
    public let ingredients: [Ingredient]

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        servings: Int? = nil,
        isTwoPerson: Bool,
        steps: [RecipeStep],
        iconSystemName: String,
        difficulty: Int,
        cookTimeMinutes: Int,
        dietaryTags: [DietaryTag] = [],
        ingredients: [Ingredient]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.servings = servings
        self.isTwoPerson = isTwoPerson
        self.steps = steps
        self.iconSystemName = iconSystemName
        self.difficulty = difficulty
        self.cookTimeMinutes = cookTimeMinutes
        self.dietaryTags = dietaryTags
        self.ingredients = ingredients
    }

    /// The ordered list of steps visible to a given role: their own steps plus every shared step.
    /// `role: nil` (solo recipes) returns the full step list, since solo steps are tagged `.solo`.
    public func track(for role: StepAssignee?) -> [RecipeStep] {
        guard let role else {
            return steps.sorted { $0.order < $1.order }
        }
        return steps
            .filter { $0.assignee == .shared || $0.assignee == role }
            .sorted { $0.order < $1.order }
    }
}
