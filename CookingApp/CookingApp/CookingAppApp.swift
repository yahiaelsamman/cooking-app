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
    @State private var storeFallbackNotice: Bool

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate

        // UI tests start from a clean persisted session (no stale "Resume Cooking") unless a
        // test passes -UITestKeepSession (e.g. to verify resume after a relaunch).
        let launchArgs = ProcessInfo.processInfo.arguments
        if launchArgs.contains("-UITesting") && !launchArgs.contains("-UITestKeepSession") {
            SessionPersistence.clear()
        }

        // The Local Network explainer is shown once per install; UI tests see it every run unless
        // a test passes -UITestSkipExplainer.
        if launchArgs.contains("-UITesting") && !launchArgs.contains("-UITestSkipExplainer") {
            UserDefaults.standard.removeObject(forKey: "hasSeenLocalNetworkExplainer")
        }

        let container: ModelContainer
        var usedFallback = false
        do {
            if ProcessInfo.processInfo.arguments.contains("-UITesting") {
                // XCUITest launches with this flag — an in-memory store means every test run
                // starts from exactly the 20 bundled recipes and nothing else (no leftover
                // custom recipes/favorites/ratings/shopping-list items from a previous run), and
                // never touches the real on-device store a person actually cooks from.
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try ModelContainer(for: Recipe.self, ShoppingListItem.self, configurations: configuration)
            } else {
                container = try ModelContainer(for: Recipe.self, ShoppingListItem.self)
            }
        } catch {
            // Don't crash-loop on launch: fall back to a temporary in-memory store (bundled
            // recipes still seed; changes made this session won't persist).
            NSLog("Could not open the recipe store, using in-memory fallback: \(error)")
            usedFallback = true
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(for: Recipe.self, ShoppingListItem.self, configurations: fallback)
            } catch {
                fatalError("Could not create even an in-memory recipe store: \(error)")
            }
        }
        modelContainer = container
        _storeFallbackNotice = State(initialValue: usedFallback)
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
                .alert("Saved recipes couldn't be opened", isPresented: $storeFallbackNotice) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Your custom recipes, favorites and ratings couldn't be loaded. Anything you change in this session won't be saved. Restarting the app may help.")
                }
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
