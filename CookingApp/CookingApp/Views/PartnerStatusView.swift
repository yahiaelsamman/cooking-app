import SwiftUI
import CookingAppCore

/// Compact, non-blocking strip showing the partner's current step, connection status, and how
/// their overall progress compares to yours. Carries its own tap gesture (that does nothing)
/// purely to absorb taps — without it, a tap here would fall through to StepView's full-screen
/// "advance" gesture underneath and accidentally skip the local user's own step.
struct PartnerStatusView: View {
    let session: CookingSessionViewModel

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

            if session.partnerConnectionState == .connected, let partnerFraction = session.partnerProgressFraction {
                DualProgressSliderView(myFraction: session.progressFraction, partnerFraction: partnerFraction)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {}
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
        default:
            return "Connecting…"
        }
    }
}
