import SwiftUI
import CookingAppCore

/// A "how do I check this is actually done" disclosure for a step's `checkHint` — renders nothing
/// for a step that doesn't have one. Callers should apply `.id(step.id)` when placing this so its
/// expanded/collapsed `@State` resets per step rather than carrying over from whatever step was
/// showing before.
struct DonenessHintView: View {
    let checkHint: String?
    let expertise: CookExpertise

    @State private var isExpanded = false

    var body: some View {
        if let checkHint {
            VStack(spacing: 10) {
                Button {
                    withAnimation(.default) { isExpanded.toggle() }
                } label: {
                    Label("How do I check?", systemImage: isExpanded ? "chevron.up.circle.fill" : "questionmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("donenessHintToggle")

                if isExpanded {
                    Text(checkHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                }
            }
            .onAppear {
                // Beginners see the practical "how do I actually tell" guidance up front, rather
                // than needing to know a hidden disclosure exists at all — everyone else starts
                // collapsed and can still opt in with a tap.
                isExpanded = expertise.prefersVerboseGuidance
            }
        }
    }
}
