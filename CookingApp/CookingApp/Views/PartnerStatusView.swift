import SwiftUI
import CookingAppCore

/// Compact, non-blocking strip showing the partner's current step, connection status, and how
/// their overall progress compares to yours. Carries its own tap gesture (that does nothing)
/// purely to absorb taps — without it, a tap here would fall through to StepView's full-screen
/// "advance" gesture underneath and accidentally skip the local user's own step.
struct PartnerStatusView: View {
    let session: CookingSessionViewModel
    /// The tap gesture on this whole card used to be a pure no-op, purely to absorb taps so they
    /// don't fall through to `StepView`'s full-screen "advance" gesture underneath. Now that
    /// there's something worth showing on tap, it still absorbs the tap either way — nothing
    /// about that original purpose changes.
    @State private var showStatusExplanation = false
    @State private var announceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(partnerLabel)
                        .font(.caption.weight(.semibold))
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                // A small preview of what the partner is doing — enough to glance at, not
                // enough to compete with your own full-screen step for attention. Tinted orange
                // to match the partner's color everywhere else (their marker in
                // DualProgressSliderView, their timer chips in TimerStackView).
                if let partnerImage = session.partnerStep?.imageSystemName,
                   session.partnerConnectionState == .connected, !session.partnerIsAway {
                    Image(systemName: partnerImage)
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)
                }
            }
            // Otherwise VoiceOver reads the dot (nothing), name, status text, and preview icon as
            // separate fragments — one label says the same thing a glance already does, and the
            // color explanation below is reachable without sight at all via the same action a
            // sighted tap triggers.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(partnerLabel). \(statusText)")
            .accessibilityHint("Double tap for more about the connection status")
            .accessibilityAction {
                showStatusExplanation = true
            }

            if session.partnerConnectionState == .connected, let partnerFraction = session.partnerProgressFraction {
                DualProgressSliderView(myFraction: session.progressFraction, partnerFraction: partnerFraction)
            }
        }
        .padding(10)
        .background(cardBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            showStatusExplanation = true
        }
        // A partner disconnecting mid-cook is easy to miss with messy hands and eyes on the
        // stove — worth a tactile nudge, scoped to just the transition *into* disconnected so
        // reconnecting or other state churn doesn't also buzz.
        .sensoryFeedback(.warning, trigger: session.partnerConnectionState) { oldValue, newValue in
            newValue == .disconnected && oldValue != .disconnected
        }
        // Status text changes silently otherwise; announce it for VoiceOver. Debounced so a
        // flapping connection speaks only the state it settles on.
        .onChange(of: session.partnerConnectionState) { _, _ in announceStatus() }
        .onChange(of: session.partnerIsAway) { _, _ in announceStatus() }
        .onDisappear { announceTask?.cancel() }
        .alert("Connection Status", isPresented: $showStatusExplanation) {
            Button("OK") {}
        } message: {
            Text(
                "Green (connected): your partner is cooking along with you. "
                    + "Blue (stepped away): their progress is saved. "
                    + "Yellow (connecting): still finding each other. "
                    + "Red (disconnected): you've lost each other, but keep cooking and you'll resync if they reconnect. "
                    + "Ended: the shared session is over and you're cooking on your own."
            )
        }
    }

    private func announceStatus() {
        announceTask?.cancel()
        guard session.partnerConnectionState != .idle else { return }
        announceTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            var announcement = AttributedString("\(partnerLabel): \(statusText)")
            announcement.accessibilitySpeechAnnouncementPriority = .high
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    // This card is a floating, tappable status control over the step content, not static
    // page background — a real fit for Liquid Glass per the skill's "functional control" rule.
    // Falls back to the existing `.thinMaterial` treatment pre-iOS 26.
    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 26, *) {
            Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10).fill(.thinMaterial)
        }
    }

    private var partnerLabel: String {
        if let name = session.partnerName, !name.isEmpty {
            return name
        }
        return session.role == .personA ? "Partner (Person B)" : "Partner (Person A)"
    }

    private var dotColor: Color {
        switch session.partnerConnectionState {
        case .connected: return session.partnerIsAway ? .blue : .green
        case .connecting, .advertising, .browsing: return .yellow
        case .disconnected: return .red
        case .idle: return .gray
        }
    }

    private var statusText: String {
        switch session.partnerConnectionState {
        case .disconnected:
            return "Partner disconnected — keep cooking, we'll resync if they reconnect."
        case .connected:
            if session.partnerIsAway {
                return "Partner stepped away — they'll pick back up from where they left off."
            }
            // Check "finished" before falling back to "Getting started…" — `partnerStep` is
            // also nil once they're past their last step, so without this check a partner who's
            // actually done looks indistinguishable from one who hasn't started yet.
            if session.partnerProgressFraction == 1.0 {
                return "Partner has finished — waiting for you!"
            }
            return session.partnerStep?.instruction ?? "Getting started…"
        case .idle:
            return "Shared session ended. You're cooking on your own."
        default:
            return "Connecting…"
        }
    }
}
