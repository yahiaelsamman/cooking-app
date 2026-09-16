import SwiftUI
import SwiftData
import UserNotifications
import CookingAppCore

@main
struct CookingAppApp: App {
    @State private var sessionStore = ActiveSessionStore()
    // Held strongly for the app's lifetime — UNUserNotificationCenter.delegate is `weak`.
    private let notificationDelegate = NotificationDelegate()
    private let modelContainer: ModelContainer

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate

        do {
            if ProcessInfo.processInfo.arguments.contains("-UITesting") {
                // XCUITest launches with this flag — an in-memory store means every test run
                // starts from exactly the 20 bundled recipes and nothing else (no leftover
                // custom recipes/favorites/ratings/shopping-list items from a previous run), and
                // never touches the real on-device store a person actually cooks from.
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                modelContainer = try ModelContainer(for: Recipe.self, ShoppingListItem.self, configurations: configuration)
            } else {
                modelContainer = try ModelContainer(for: Recipe.self, ShoppingListItem.self)
            }
        } catch {
            fatalError("Could not create the recipe store: \(error)")
        }
        RecipeSeeder.seedIfNeeded(context: modelContainer.mainContext)
        sessionStore.restoreIfNeeded(modelContext: modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RecipeListView()
                .environment(sessionStore)
        }
        .modelContainer(modelContainer)
    }
}
