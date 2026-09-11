import CookingAppCore

/// Every pushable destination in the app, driven off a single `NavigationPath` owned by
/// `RecipeListView`. Centralizing routes here makes "pop to root" (used when a recipe
/// completes) a one-line `path = NavigationPath()` regardless of how deep the stack is.
enum Route: Hashable {
    case detail(Recipe)
    case peerConnection(Recipe)
    case steps(CookingSessionViewModel)
}
