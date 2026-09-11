import SwiftUI
import UserNotifications
import CookingAppCore

@main
struct CookingAppApp: App {
    @State private var sessionStore = ActiveSessionStore()
    // Held strongly for the app's lifetime — UNUserNotificationCenter.delegate is `weak`.
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            RecipeListView()
                .environment(sessionStore)
        }
    }
}
