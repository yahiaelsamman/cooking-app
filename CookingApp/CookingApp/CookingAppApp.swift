import SwiftUI
import CookingAppCore

@main
struct CookingAppApp: App {
    @State private var sessionStore = ActiveSessionStore()

    var body: some Scene {
        WindowGroup {
            RecipeListView()
                .environment(sessionStore)
        }
    }
}
