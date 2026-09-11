import SwiftUI
import UIKit

/// Disables the system's edge-swipe-to-pop gesture on the enclosing `UINavigationController`
/// while this view is on screen, restoring it when the view leaves. Used on `StepView` so a
/// stray edge swipe during a two-person cook session can't accidentally pop back to the connect
/// screen and drop the appearance of the partner connection — `StepView` has its own drag
/// gesture for step navigation instead (see `stepSwipeGesture` in StepView.swift).
///
/// SwiftUI has no first-party API for this; `navigationBarBackButtonHidden` only hides the
/// button, it doesn't disable the interactive pop gesture.
private struct SwipeBackDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.parent?.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: ()) {
        uiViewController.parent?.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
}

extension View {
    func disablesInteractiveSwipeBack() -> some View {
        background(SwipeBackDisabler())
    }
}
