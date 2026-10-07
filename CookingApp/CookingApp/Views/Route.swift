import CookingAppCore

/// Every pushable destination in the app, driven off a single typed `[Route]` path owned by
/// `RecipeListView`. Centralizing routes here makes "pop to root" (used when a recipe
/// completes) a one-line `path = []` regardless of how deep the stack is.
enum Route: Hashable {
    case detail(Recipe)
    /// The servings scale picked on the recipe screen rides along so the two-person session's
    /// ingredient checklist matches it, same as a solo session.
    case peerConnection(Recipe, servingsScaleFactor: Double)
    case steps(CookingSessionViewModel)
}
