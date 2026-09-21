import SwiftUI
import CookingAppCore

/// The tappable timer icon shown on steps that have a `timerSeconds` value (e.g. "Simmer the
/// sauce"). Tapping starts a real countdown, owned by `CookingSessionViewModel` so it keeps
/// running even if you navigate to a different step; tapping again while running cancels it.
struct StepTimerControl: View {
    let step: RecipeStep
    let session: CookingSessionViewModel
    /// Notified after a real tap on either button — lets `StepView`'s one-time "here's how
    /// timers work" walkthrough tip advance when this control is actually used, without this
    /// leaf view needing to know anything about `AppTour` itself.
    var onInteract: (() -> Void)? = nil

    var body: some View {
        timerButton
    }

    @ViewBuilder
    private var timerButton: some View {
        if let seconds = step.timerSeconds {
            if let running = session.activeTimer(for: step) {
                Button {
                    session.cancelTimer(for: step)
                    onInteract?()
                } label: {
                    Label(Self.formatted(running.remainingSeconds), systemImage: "timer")
                        .font(.title3.monospacedDigit().weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                // Without this, VoiceOver reads only the raw digits ("3 59, button") with no
                // indication tapping cancels the timer.
                .accessibilityLabel("Cancel timer")
                .accessibilityValue("\(Self.spoken(running.remainingSeconds)) remaining")
                .accessibilityInputLabels(["Cancel timer", "Timer"])
                .tourAnchor("stepTimerButton")
            } else {
                Button {
                    session.startTimer(for: step)
                    onInteract?()
                } label: {
                    Label("Start \(Self.formatted(seconds)) timer", systemImage: "timer")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Start \(Self.spoken(seconds)) timer")
                .accessibilityInputLabels(["Start timer", "Start \(Self.spoken(seconds)) timer"])
                .tourAnchor("stepTimerButton")
            }
        }
    }

    /// "3 minutes, 59 seconds" — VoiceOver reads the `m:ss` form as "3 colon 59".
    static func spoken(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide)
        )
    }

    static func formatted(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
