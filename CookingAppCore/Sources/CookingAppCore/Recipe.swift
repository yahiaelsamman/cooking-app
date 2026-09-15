import Foundation
import SwiftData

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

/// The only `@Model` type in this app — a real on-device database record, queryable via
/// `@Query` and persisted by SwiftData across launches. `RecipeStep`/`Ingredient`/`DietaryTag`
/// deliberately stay plain `Codable` value types embedded on this model (as attributes, not
/// SwiftData relationships): they never need independent identity or querying outside their
/// parent recipe, so giving them their own `@Model`/relationship machinery would just be
/// SwiftData relationship-modeling complexity (inverse-relationship ambiguity between two
/// same-type to-many relationships on one parent, in particular) for no real benefit.
@Model
public final class Recipe {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var summary: String
    public var servings: Int?
    /// The solo-cooking step list — always present, every step tagged `.solo`. Written as its
    /// own version, not derived from `twoPersonSteps`: it reads naturally for one person (no
    /// "Both:" phrasing, no assignee-based hue shifts in the UI) and its cook time reflects doing
    /// everything sequentially rather than splitting labor.
    public var soloSteps: [RecipeStep]
    /// The two-person task split, if this recipe has one. `nil` means there's no sensible way to
    /// divide this recipe's steps between two people — two-person mode simply isn't offered for
    /// it at all (see `supportsTwoPerson`), rather than falling back to some generic mirror of
    /// the solo steps.
    public var twoPersonSteps: [RecipeStep]?
    /// SF Symbol shown as this recipe's "photo" on the list/overview screens.
    public var iconSystemName: String
    /// Name of a bundled hero photo in the app's asset catalog, if one has been sourced for this
    /// recipe yet — `nil` (the default for every recipe so far) means fall back to the
    /// `iconSystemName`-based placeholder card. Deliberately per-recipe, not all-or-nothing: real
    /// photos can land one recipe at a time as they're sourced/approved.
    public var heroImageName: String?
    /// 1...3, rendered as filled-out-of-3 stars.
    public var difficulty: Int
    /// 0...3, rendered as filled-out-of-3 flames. 0 means not spicy at all.
    public var spiceLevel: Int
    public var soloCookTimeMinutes: Int
    /// `nil` when `twoPersonSteps` is `nil`.
    public var twoPersonCookTimeMinutes: Int?
    public var dietaryTags: [DietaryTag]
    public var ingredients: [Ingredient]

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        servings: Int? = nil,
        soloSteps: [RecipeStep],
        twoPersonSteps: [RecipeStep]? = nil,
        iconSystemName: String,
        heroImageName: String? = nil,
        difficulty: Int,
        spiceLevel: Int = 0,
        soloCookTimeMinutes: Int,
        twoPersonCookTimeMinutes: Int? = nil,
        dietaryTags: [DietaryTag] = [],
        ingredients: [Ingredient]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.servings = servings
        self.soloSteps = soloSteps
        self.twoPersonSteps = twoPersonSteps
        self.iconSystemName = iconSystemName
        self.heroImageName = heroImageName
        self.difficulty = difficulty
        self.spiceLevel = spiceLevel
        self.soloCookTimeMinutes = soloCookTimeMinutes
        self.twoPersonCookTimeMinutes = twoPersonCookTimeMinutes
        self.dietaryTags = dietaryTags
        self.ingredients = ingredients
    }

    /// Whether two-person mode should be offered for this recipe at all.
    public var supportsTwoPerson: Bool { twoPersonSteps != nil }

    public func cookTimeMinutes(forTwoPerson: Bool) -> Int {
        forTwoPerson ? (twoPersonCookTimeMinutes ?? soloCookTimeMinutes) : soloCookTimeMinutes
    }

    /// The ordered list of steps visible to a given role.
    /// - `role: nil` — solo mode: `soloSteps`, in order.
    /// - `role: .personA` / `.personB` — that person's own steps plus every `.shared` step from
    ///   `twoPersonSteps`. Falls back to `soloSteps` if this recipe has no two-person steps at
    ///   all — shouldn't happen in practice, since the UI only offers two-person mode when
    ///   `supportsTwoPerson` is true, but keeps this safe to call regardless.
    public func track(for role: StepAssignee?) -> [RecipeStep] {
        guard let role, let twoPersonSteps else {
            return soloSteps.sorted { $0.order < $1.order }
        }
        return twoPersonSteps
            .filter { $0.assignee == .shared || $0.assignee == role }
            .sorted { $0.order < $1.order }
    }
}

// MARK: - Identifiable / Hashable

// @Model classes don't get Swift's automatic Equatable/Hashable synthesis (that only applies to
// structs/enums) — these are identity-based on `id`, which is what NavigationPath/Route usage and
// SwiftData's own duplicate-seeding checks both rely on.
extension Recipe: Identifiable {}

extension Recipe: Hashable {
    public static func == (lhs: Recipe, rhs: Recipe) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
