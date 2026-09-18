import Foundation
import SwiftData

public enum StepAssignee: String, Codable, Sendable {
    case solo
    case shared
    case personA
    case personB
}

public struct RecipeStep: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// `var`, not `let` — despite every other use of a `RecipeStep` treating it as an immutable
    /// value (a recipe is seeded once and never mutated except via `RecipeEditorView`), these need
    /// to be mutable so SwiftUI's `Binding` dynamic member lookup (`ForEach($steps) { $step in
    /// TextField(text: $step.instruction) }`) can produce a writable sub-binding at all.
    public var order: Int
    public var instruction: String
    public var assignee: StepAssignee
    /// Drives the live countdown in StepTimerControl — nil means the step has no timer at all.
    public var timerSeconds: Int?
    /// SF Symbol name shown as this step's illustration when `stepImageName` is nil.
    public var imageSystemName: String
    /// Name of a bundled step illustration in the app's asset catalog, if one has been sourced for
    /// this step yet — nil (the default for every step so far) falls back to the plain SF Symbol
    /// placeholder in `imageSystemName`, same "real asset when we have it, generic stand-in
    /// otherwise" pattern `Recipe.heroImageName` already uses.
    public var stepImageName: String?
    /// A plain-language way to tell this step is actually done, shown behind a "How do I check?"
    /// disclosure in `StepView` — nil means this step has no ambiguous doneness call to make.
    /// Deliberately separate from `instruction`: a doneness temperature buried in the middle of a
    /// sentence ("...until cooked through (165°F internal temperature)") reads fine to an
    /// experienced cook but doesn't tell a beginner *how* to check it (do they own a thermometer?
    /// where do they put it?) — this field is where that practical guidance lives instead of being
    /// squeezed into the instruction text itself.
    public var checkHint: String?

    public init(id: UUID = UUID(), order: Int, instruction: String, assignee: StepAssignee, timerSeconds: Int? = nil, imageSystemName: String, stepImageName: String? = nil, checkHint: String? = nil) {
        self.id = id
        self.order = order
        self.instruction = instruction
        self.assignee = assignee
        self.timerSeconds = timerSeconds
        self.imageSystemName = imageSystemName
        self.stepImageName = stepImageName
        self.checkHint = checkHint
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
    public var id: UUID
    /// `var` for the same reason as `RecipeStep`'s properties — see its doc comment.
    public var name: String
    public var amount: String

    public init(id: UUID = UUID(), name: String, amount: String) {
        self.id = id
        self.name = name
        self.amount = amount
    }

    /// `amount` rescaled to a different serving count, for `RecipeDetailView`'s servings
    /// stepper. Only the leading quantity is touched — a whole number ("2"), a decimal ("1.5"),
    /// a simple fraction ("1/2"), or a mixed number ("1 1/2") — everything after it (a unit,
    /// "small"/"large", or nothing at all) is preserved verbatim. Amounts with no leading number
    /// at all ("A pinch," "To taste," "As needed") come back unchanged: there's nothing in them
    /// to scale, and guessing would silently turn real recipe content into garbage.
    ///
    /// Deliberately doesn't attempt unit conversion, unicode vulgar fractions (½, ¾), or ranges
    /// ("2-3") — none of those appear in this app's actual ingredient data (see
    /// `SampleRecipes.swift`), and adding support for formats nothing uses yet would be exactly
    /// the kind of speculative complexity this project's conventions steer away from.
    public func scaledAmount(by factor: Double) -> String {
        Ingredient.scale(amount, by: factor)
    }

    static func scale(_ amount: String, by factor: Double) -> String {
        guard factor.isFinite, factor > 0, let quantity = parseLeadingQuantity(amount) else {
            return amount
        }
        return formatQuantity(quantity.value * factor) + quantity.remainder
    }

    /// Splits `amount` into a leading numeric value and everything after it, or `nil` if it
    /// doesn't start with a number at all.
    private static func parseLeadingQuantity(_ amount: String) -> (value: Double, remainder: String)? {
        var rest = Substring(amount)
        guard let wholeDigits = consumeDigits(&rest) else { return nil }
        let whole = Double(wholeDigits)!

        // Decimal: "1.5 cups" → whole part "1", fractional digits "5".
        if rest.first == "." {
            var afterDot = rest
            afterDot.removeFirst()
            if let fractionDigits = consumeDigits(&afterDot) {
                return (Double(wholeDigits + "." + fractionDigits)!, String(afterDot))
            }
        }

        // Fraction with no leading whole part: "1/2 cup".
        if rest.first == "/" {
            var afterSlash = rest
            afterSlash.removeFirst()
            if let denominatorDigits = consumeDigits(&afterSlash), let denominator = Double(denominatorDigits), denominator != 0 {
                return (whole / denominator, String(afterSlash))
            }
        }

        // Mixed number: "1 1/2 tsp" — only if what follows the space is itself a fraction;
        // otherwise the space just separates the number from a unit/word ("1 small").
        if rest.first == " " {
            var afterSpace = rest
            afterSpace.removeFirst()
            var probe = afterSpace
            if let numeratorDigits = consumeDigits(&probe), probe.first == "/" {
                var afterSlash = probe
                afterSlash.removeFirst()
                if let denominatorDigits = consumeDigits(&afterSlash),
                   let numerator = Double(numeratorDigits),
                   let denominator = Double(denominatorDigits),
                   denominator != 0 {
                    return (whole + numerator / denominator, String(afterSlash))
                }
            }
        }

        // Plain whole number, either directly followed by a unit ("200g") or by a
        // non-fraction word after a space ("1 small").
        return (whole, String(rest))
    }

    private static func consumeDigits(_ substring: inout Substring) -> String? {
        var digits = ""
        while let character = substring.first, character.isASCII, character.isNumber {
            digits.append(character)
            substring.removeFirst()
        }
        return digits.isEmpty ? nil : digits
    }

    /// Renders a scaled quantity back to text — a whole number as-is, a near-whole value snapped
    /// to it (guards against floating-point noise like `1.9999999`), and anything else as the
    /// nearest common cooking fraction (halves/thirds/quarters/eighths) if one is close enough,
    /// falling back to a trimmed decimal otherwise.
    private static func formatQuantity(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0" }

        let whole = value.rounded(.down)
        let fractional = value - whole

        if fractional < 0.02 { return formatWhole(whole) }
        if fractional > 0.98 { return formatWhole(whole + 1) }

        for denominator in [2, 3, 4, 8] {
            let numerator = (fractional * Double(denominator)).rounded()
            guard numerator > 0, numerator < Double(denominator) else { continue }
            guard abs(fractional - numerator / Double(denominator)) < 0.02 else { continue }
            let divisor = gcd(Int(numerator), denominator)
            let fractionText = "\(Int(numerator) / divisor)/\(denominator / divisor)"
            return whole > 0 ? "\(formatWhole(whole)) \(fractionText)" : fractionText
        }

        return trimmedDecimal(value)
    }

    private static func formatWhole(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private static func trimmedDecimal(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
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

    // MARK: - User data
    //
    // Everything below is set by the person using the app, never by the bundled recipe content
    // itself — `RecipeSeeder` never overwrites any of these on an already-seeded recipe (see its
    // doc comment). Every new field here is given an inline default (rather than relying solely on
    // the initializer's default) specifically so SwiftData's automatic lightweight migration can
    // backfill it on rows persisted before the field existed, without a manual migration plan.

    /// Starred/pinned by the user — surfaced via a "Favorites only" filter and a swipe action on
    /// the recipe list, independent of cooking mode or sort order.
    public var isFavorite: Bool = false
    /// 1...5, or `nil` if never rated. Set via `StarRatingView` on the recipe detail screen;
    /// tapping the currently-set top star again clears it back to `nil` rather than getting stuck.
    public var personalRating: Int?
    /// Free-text notes the user writes about this recipe (what they changed, how it turned out,
    /// what to try next time) — separate from `summary`, which is fixed recipe content.
    public var personalNotes: String = ""
    /// Incremented once per completed cooking session (solo or two-person), the moment
    /// `CookingSessionViewModel.isComplete` first becomes true — see `StepView`'s completion
    /// tracking. Not decremented by "Go Back" from the completion screen; a genuine re-completion
    /// after going back counts again.
    public var timesCooked: Int = 0
    /// Set alongside `timesCooked`; `nil` until the first completion.
    public var lastCookedDate: Date?
    /// This recipe's position in the user's own manual ordering ("My Order" in `RecipeListView`).
    /// Assigned sequentially at seed time in bundle order; a user drag-reorder rewrites every
    /// recipe's value to match the new order. Independent of alphabetical/rating sort modes, which
    /// don't read this field at all.
    public var sortOrder: Int = 0
    /// `true` only for a recipe created through `RecipeEditorView`, never for a bundled
    /// `SampleRecipes` one. Deliberately kept separate from "has the user edited this" — editing
    /// and deleting are both restricted to user-created recipes for now (see `RecipeEditorView`):
    /// editing a curated bundled recipe's authored content is out of scope, and deleting one would
    /// need `RecipeSeeder` to track a tombstone (see its doc comment) so it doesn't just come back
    /// on the next launch — neither problem exists for a recipe that was never bundled to begin
    /// with.
    public var isUserCreated: Bool = false

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
        ingredients: [Ingredient],
        isFavorite: Bool = false,
        personalRating: Int? = nil,
        personalNotes: String = "",
        timesCooked: Int = 0,
        lastCookedDate: Date? = nil,
        sortOrder: Int = 0,
        isUserCreated: Bool = false
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
        self.isFavorite = isFavorite
        self.personalRating = personalRating
        self.personalNotes = personalNotes
        self.timesCooked = timesCooked
        self.lastCookedDate = lastCookedDate
        self.sortOrder = sortOrder
        self.isUserCreated = isUserCreated
    }

    /// Whether two-person mode should be offered for this recipe at all.
    public var supportsTwoPerson: Bool { twoPersonSteps != nil }

    /// The `sortOrder` a newly-added recipe should get to land at the end of "My Order" — shared
    /// by `RecipeSeeder` (appending missing bundled recipes) and `RecipeEditorView` (creating a
    /// user-made one), so both agree on the same "append after the current max" policy rather
    /// than encoding it twice.
    public static func nextSortOrder(after existing: [Recipe]) -> Int {
        (existing.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Overwrites every bundled/curated field (everything above the "User data" mark) with
    /// `other`'s values, leaving `id` and every user-data field on `self` completely untouched.
    /// Used by `RecipeSeeder` to keep an already-seeded bundled recipe's content (steps, images,
    /// ingredients, ...) in sync with `SampleRecipes.swift` on every launch, without ever
    /// touching a favorite, rating, note, or the user's own sort order.
    public func updateBundledContent(from other: Recipe) {
        title = other.title
        summary = other.summary
        servings = other.servings
        soloSteps = other.soloSteps
        twoPersonSteps = other.twoPersonSteps
        iconSystemName = other.iconSystemName
        heroImageName = other.heroImageName
        difficulty = other.difficulty
        spiceLevel = other.spiceLevel
        soloCookTimeMinutes = other.soloCookTimeMinutes
        twoPersonCookTimeMinutes = other.twoPersonCookTimeMinutes
        dietaryTags = other.dietaryTags
        ingredients = other.ingredients
    }

    public func cookTimeMinutes(forTwoPerson: Bool) -> Int {
        forTwoPerson ? (twoPersonCookTimeMinutes ?? soloCookTimeMinutes) : soloCookTimeMinutes
    }

    /// Whether this recipe should show up for a given search query, used by `RecipeListView`'s
    /// search field. Matches against title, summary, ingredient names, and dietary tag labels —
    /// deliberately not step instructions, which would surface unrelated recipes on very common
    /// words ("stir," "pan") rather than helping someone find a dish by name or what's in it.
    /// `localizedStandardContains` (not a plain substring check) gives case- and
    /// diacritic-insensitive matching consistent with Finder/Spotlight-style search. An empty or
    /// whitespace-only query matches every recipe.
    public func matchesSearch(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if title.localizedStandardContains(trimmed) { return true }
        if summary.localizedStandardContains(trimmed) { return true }
        if ingredients.contains(where: { $0.name.localizedStandardContains(trimmed) }) { return true }
        if dietaryTags.contains(where: { $0.label.localizedStandardContains(trimmed) }) { return true }
        return false
    }

    /// Whether this recipe satisfies every one of `requiredTags`, used by `RecipeListView`'s
    /// dietary filter chips. Deliberately AND, not OR: someone filtering by both "Vegan" and
    /// "Nut-Free" has two real restrictions to satisfy at once, not a preference for either one —
    /// OR semantics would surface a vegan recipe with nuts in it, which is the one thing this
    /// filter exists to prevent. An empty set matches every recipe (no filter applied).
    public func matchesDietaryFilter(_ requiredTags: Set<DietaryTag>) -> Bool {
        requiredTags.isSubset(of: Set(dietaryTags))
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
