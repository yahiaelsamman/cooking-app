import UserNotifications
import CookingAppCore
import os

/// Schedules/cancels local notifications for a step's timer, keyed by the step's own id so a
/// cancel always targets the right pending request even with multiple timers stacked at once.
/// Stateless — everything goes straight through `UNUserNotificationCenter.current()` — so this
/// is a namespace of static functions rather than an instance.
enum NotificationScheduler {
    private static let logger = Logger(subsystem: "com.yahia.cookingapp", category: "NotificationScheduler")

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.error("Notification authorization request failed: \(error, privacy: .public)")
            } else if !granted {
                // Not logged as an error — declining is a legitimate, expected choice. `StepView`
                // shows a hint with a Settings link while a timer runs and this is denied.
                logger.notice("Notification authorization was denied.")
            }
        }
    }

    /// True when the user has explicitly turned notifications off — `.notDetermined` isn't
    /// "denied", it just hasn't been asked yet.
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    static func schedule(step: RecipeStep, durationSeconds: Int) {
        guard durationSeconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Timer Finished"
        content.body = step.instruction
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(durationSeconds), repeats: false)
        // Same identifier per step, so re-scheduling (e.g. as the app goes to the background)
        // replaces the earlier request rather than stacking a second one.
        let request = UNNotificationRequest(identifier: identifier(for: step), content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        Task {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .denied:
                logger.notice("Not scheduling a timer notification: notifications are denied.")
                return
            case .notDetermined:
                // Never asked yet (e.g. the permission prompt was skipped or dismissed): ask now,
                // so a first-ever timer isn't silently left without a notification.
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                guard granted else { return }
            default:
                break
            }
            do {
                try await center.add(request)
            } catch {
                logger.error("Failed to schedule timer notification: \(error, privacy: .public)")
            }
        }
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
