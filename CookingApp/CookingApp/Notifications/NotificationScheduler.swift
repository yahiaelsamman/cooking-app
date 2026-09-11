import UserNotifications
import CookingAppCore

/// Schedules/cancels local notifications for a step's timer, keyed by the step's own id so a
/// cancel always targets the right pending request even with multiple timers stacked at once.
/// Stateless — everything goes straight through `UNUserNotificationCenter.current()` — so this
/// is a namespace of static functions rather than an instance.
enum NotificationScheduler {
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(step: RecipeStep, durationSeconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Timer Finished"
        content.body = step.instruction
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(durationSeconds), repeats: false)
        let request = UNNotificationRequest(identifier: identifier(for: step), content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Cancels both a still-pending request (timer cancelled early) and an already-delivered one
    /// (timer finished while the app was foregrounded, where the in-app alert already covered it).
    static func cancel(step: RecipeStep) {
        let id = identifier(for: step)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    private static func identifier(for step: RecipeStep) -> String {
        "timer-\(step.id.uuidString)"
    }
}
