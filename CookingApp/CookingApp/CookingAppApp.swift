import SwiftUI
import SwiftData
import UserNotifications
import CookingAppCore

@main
struct CookingAppApp: App {
    @State private var sessionStore: ActiveSessionStore
    @Environment(\.scenePhase) private var scenePhase
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
        // Restore into a local store and hand *that exact instance* to `@State`. Reading a
        // `@State` property from `init` (before the app is installed) doesn't reliably give back
        // the instance the views later receive, which left "Resume Cooking" empty after a relaunch.
        let store = ActiveSessionStore()
        store.restoreIfNeeded(modelContext: modelContainer.mainContext)
        _sessionStore = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RecipeListView()
                .environment(sessionStore)
                .environment(\.notificationPresentationState, notificationDelegate.presentationState)
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, phase in
            // The one-second ticker doesn't run while iOS has the app suspended, so timers are
            // measured against real end dates: catch up the moment the app is visible again, and
            // make sure every running timer has a system notification waiting as the app leaves.
            switch phase {
            case .active: sessionStore.currentSession?.refreshTimers()
            case .background: sessionStore.currentSession?.rescheduleTimerNotifications()
            default: break
            }
        }
    }
}
