import SwiftUI
import CookingAppCore

/// A compact stack of chips for every timer running somewhere other than the step currently on
/// screen — your own timers on other steps, and (in a two-person session) your partner's. Each
/// chip names the task it's timing, since once you've navigated away from that step you'd
/// otherwise have no way to tell which "3:59 remaining" belongs to which thing on the stove.
struct TimerStackView: View {
    let timers: [TimerChipInfo]

    var body: some View {
        if !timers.isEmpty {
            // Chips float over the active step's content and several can stack at once —
            // a GlassEffectContainer lets iOS 26+ blend/render them as one related group
            // instead of each chip paying its own compositing cost.
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 6) {
                    VStack(spacing: 6) {
                        ForEach(timers) { info in
                            chip(for: info)
                        }
                    }
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(timers) { info in
                        chip(for: info)
                    }
                }
            }
        }
    }

    private func chip(for info: TimerChipInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
            Text(info.step.instruction)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(StepTimerControl.formatted(info.remainingSeconds))
                .monospacedDigit()
        }
        .font(.caption.weight(.medium))
        // Matches DualProgressSliderView's marker colors: mine = accentColor, partner = orange —
        // so "the partner's color" means the same thing everywhere it shows up.
        .foregroundStyle(info.isMine ? Color.accentColor : .orange)
        .padding(8)
        .background(chipBackground(isMine: info.isMine))
        .contentShape(Rectangle())
        .onTapGesture {} // absorb — don't advance the current step when tapping a timer chip
        // Otherwise reads as three disconnected fragments ("timer" image, instruction, digits) —
        // one label makes it clear whose timer it is and how much time is left.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(info.isMine ? "Your timer" : "Partner's timer"): \(info.step.instruction), \(StepTimerControl.formatted(info.remainingSeconds)) remaining")
    }

    @ViewBuilder
    private func chipBackground(isMine: Bool) -> some View {
        let tint = isMine ? Color.accentColor : Color.orange
        if #available(iOS 26, *) {
            Color.clear.glassEffect(.regular.tint(tint.opacity(0.35)), in: RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.12))
        }
    }
}

struct TimerChipInfo: Identifiable {
    let step: RecipeStep
    let remainingSeconds: Int
    let isMine: Bool
    var id: UUID { step.id }
}
