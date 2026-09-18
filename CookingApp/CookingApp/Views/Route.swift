import CookingAppCore

/// Every pushable destination in the app, driven off a single typed `[Route]` path owned by
/// `RecipeListView`. Centralizing routes here makes "pop to root" (used when a recipe
/// completes) a one-line `path = []` regardless of how deep the stack is.
enum Route: Hashable {
    case detail(Recipe)
    case peerConnection(Recipe)
    case steps(CookingSessionViewModel)
}
