import SwiftUI
import UserNotifications

/// Whether `StepView`'s own in-app "timer finished" banner is currently able to show up — i.e.
/// whether `StepView` is the app's visible screen right now. `NotificationDelegate` reads this to
/// decide whether the system notification banner would be a redundant duplicate (StepView already
/// has its own in-app surface for the same event) or is actually the *only* signal the user will
/// get (the user navigated back to `RecipeListView` while a timer kept running in
/// `CookingSessionViewModel`, so there's no in-app surface to suppress the system banner in favor
/// of).
///
/// Written from the main actor by `StepView.onAppear`/`.onDisappear`. Read from
/// `UNUserNotificationCenterDelegate` callbacks, which the system doesn't guarantee to deliver on
/// the main thread — hence the lock rather than a plain stored property.
final class NotificationPresentationState: @unchecked Sendable {
    private let lock = NSLock()
    private var _isStepViewVisible = false

    var isStepViewVisible: Bool {
        get { lock.withLock { _isStepViewVisible } }
        set { lock.withLock { _isStepViewVisible = newValue } }
    }
}

private struct NotificationPresentationStateKey: EnvironmentKey {
    static let defaultValue = NotificationPresentationState()
}

extension EnvironmentValues {
    var notificationPresentationState: NotificationPresentationState {
        get { self[NotificationPresentationStateKey.self] }
        set { self[NotificationPresentationStateKey.self] = newValue }
    }
}

/// Suppresses the system notification banner/sound while `StepView` is on screen — it already
/// shows its own in-app alert + haptic when a timer finishes in that case (see `StepView`). When
/// `StepView` isn't visible, there's no in-app surface covering the event, so the system banner is
/// let through instead of silently dropping the only signal the user would otherwise get.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    let presentationState = NotificationPresentationState()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(presentationState.isStepViewVisible ? [] : [.banner, .sound])
    }
}
