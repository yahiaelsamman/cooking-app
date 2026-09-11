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
            modelContainer = try ModelContainer(for: Recipe.self)
        } catch {
            fatalError("Could not create the recipe store: \(error)")
        }
        RecipeSeeder.seedIfNeeded(context: modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RecipeListView()
                .environment(sessionStore)
        }
        .modelContainer(modelContainer)
    }
}
