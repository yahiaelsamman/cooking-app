import SwiftUI

/// Finishing the recipe requires a 1-second hold rather than the usual single tap/swipe — a
/// plain tap on the final step is too easy to trigger by accident, and there's no "undo" for
/// accidentally landing on the completion screen beyond backing out again.
struct HoldToFinishButton: View {
    let onFinish: () -> Void

    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0

    private let holdDuration: Double = 1.0
    /// Prepared while the button is held, so the first-ever haptic doesn't spin up the taptic
    /// engine on the main thread at the moment the recipe finishes.
    private let feedback = UINotificationFeedbackGenerator()
    /// Scales the button's frame with Dynamic Type so the two-line "Hold to Finish" label has
    /// room to grow into at the largest accessibility text sizes instead of clipping against a
    /// fixed 110×110 circle.
    @ScaledMetric(relativeTo: .caption) private var diameter: CGFloat = 110

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 6)

            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(isHolding ? .linear(duration: holdDuration) : .easeOut(duration: 0.15), value: holdProgress)

            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Hold to\nFinish")
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 50) {
            finish()
            isHolding = false
            holdProgress = 0
        } onPressingChanged: { pressing in
            isHolding = pressing
            holdProgress = pressing ? 1 : 0
            if pressing { feedback.prepare() }
        }
        // A long-press gesture has no reliable VoiceOver equivalent — without this, the one
        // control that finishes a solo cook-through would be effectively unreachable by a
        // screen-reader user. `accessibilityAction` adds a real alternate path (a plain double
        // tap) alongside the hold gesture; it doesn't remove the hold requirement for anyone not
        // using VoiceOver, so the accidental-tap protection this button exists for is unaffected.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Finish Recipe")
        .accessibilityInputLabels(["Finish Recipe", "Finish", "Hold to Finish"])
        .accessibilityHint("Double tap to finish the recipe.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            finish()
        }
    }

    /// Fires the haptic directly rather than via `.sensoryFeedback`: `onFinish()` swaps this view
    /// out for the completion screen, so a state-triggered haptic could be torn down before it plays.
    private func finish() {
        feedback.notificationOccurred(.success)
        onFinish()
    }
}
