import SwiftUI

/// Finishing the recipe requires a 2-second hold rather than the usual single tap/swipe — a
/// plain tap on the final step is too easy to trigger by accident, and there's no "undo" for
/// accidentally landing on the completion screen beyond backing out again.
struct HoldToFinishButton: View {
    let onFinish: () -> Void

    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0

    private let holdDuration: Double = 2.0

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
        .frame(width: 110, height: 110)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 50) {
            onFinish()
            isHolding = false
            holdProgress = 0
        } onPressingChanged: { pressing in
            isHolding = pressing
            holdProgress = pressing ? 1 : 0
        }
    }
}
