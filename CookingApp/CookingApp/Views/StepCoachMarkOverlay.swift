import SwiftUI
import CookingAppCore

/// A one-time explainer for `StepView`'s gestures, shown the first time anyone ever reaches the
/// step screen. Nothing in the app previously told a first-time cook that the screen is
/// tap/swipe-driven at all — see `hasSeenStepCoachMarks` in `StepView`, the only place this is
/// dismissed (which also permanently persists the flag).
struct StepCoachMarkOverlay: View {
    let expertise: CookExpertise
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)

                Text("Cooking Hands-Free")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(tips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.8))
                            Text(tip)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .font(.body)
                .padding(.horizontal, 12)

                Button("Got it") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .accessibilityIdentifier("stepCoachMarkDismissButton")
            }
            .padding(28)
            .frame(maxWidth: 360)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cooking hands-free tips: \(tips.joined(separator: " "))")
        .accessibilityHint("Double tap to dismiss")
        .accessibilityAction { onDismiss() }
        .transition(.opacity)
    }

    private var tips: [String] {
        switch expertise {
        case .beginner, .intermediate:
            return [
                "Tap anywhere, or swipe left, to move to the next step.",
                "Swipe right, or use the back arrow, to go to the previous step.",
                "On the last step, press and hold the checkmark to finish."
            ]
        case .experienced:
            return [
                "Tap or swipe to move through steps; hold the checkmark to finish."
            ]
        }
    }
}
