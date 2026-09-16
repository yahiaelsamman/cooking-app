import Foundation

/// How comfortable the person cooking is in the kitchen — set once during onboarding (see
/// `WelcomeNameView`) and editable afterward from `RecipeListView`. Purely a presentation lever
/// for now: it controls how much hand-holding `StepView` shows (doneness hints expanded by
/// default, a fuller gesture coach-mark) rather than the actual recipe content, since splitting a
/// single authored step into finer-grained beginner steps is a content-authoring problem, not a
/// rendering one — see `SampleRecipes.swift`, which has exactly one step list per mode today.
public enum CookExpertise: String, Codable, CaseIterable, Sendable {
    case beginner
    case intermediate
    case experienced

    public var label: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Comfortable"
        case .experienced: return "Experienced"
        }
    }

    /// Beginners get every doneness hint expanded up front and the fullest gesture walkthrough;
    /// everyone else starts collapsed/condensed and can still opt in with a tap.
    public var prefersVerboseGuidance: Bool {
        self == .beginner
    }
}
