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
            VStack(spacing: 6) {
                ForEach(timers) { info in
                    chip(for: info)
                }
            }
        }
    }

    private func chip(for info: TimerChipInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .foregroundStyle(info.isMine ? Color.accentColor : .orange)
            Text(info.step.instruction)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(StepTimerControl.formatted(info.remainingSeconds))
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        // Matches DualProgressSliderView's marker colors: mine = accentColor, partner = orange —
        // so "the partner's color" means the same thing everywhere it shows up. Only the icon and
        // background carry it; the text stays primary so it keeps its contrast on the tinted background.
        .foregroundStyle(.primary)
        .padding(12)
        .background(chipBackground(isMine: info.isMine))
        .contentShape(Rectangle())
        .onTapGesture {} // absorb — don't advance the current step when tapping a timer chip
        // Otherwise reads as three disconnected fragments ("timer" image, instruction, digits) —
        // one label makes it clear whose timer it is and how much time is left.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(info.isMine ? "Your timer" : "Partner's timer"): \(info.step.instruction)")
        .accessibilityValue("\(StepTimerControl.spoken(info.remainingSeconds)) remaining")
    }

    // Opaque-ish on purpose: these sit over a tinted step background and must stay readable at a
    // glance from across the counter, which translucent glass didn't guarantee.
    private func chipBackground(isMine: Bool) -> some View {
        let tint = isMine ? Color.accentColor : Color.orange
        return ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground))
            RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.18))
            RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.6), lineWidth: 1.5)
        }
    }
}

struct TimerChipInfo: Identifiable {
    let step: RecipeStep
    let remainingSeconds: Int
    let isMine: Bool
    var id: String { "\(isMine ? "me" : "partner")-\(step.id.uuidString)" }
}
