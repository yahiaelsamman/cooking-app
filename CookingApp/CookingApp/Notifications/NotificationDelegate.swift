import UserNotifications

/// Suppresses the system notification banner/sound while the app is in the foreground — we
/// already show our own in-app alert + haptic when a timer finishes in that case (see
/// `StepView`). The scheduled notification exists for when the app *isn't* in the foreground;
/// showing both there would just be a duplicate alert for the same event.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
