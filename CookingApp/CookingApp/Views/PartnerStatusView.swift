import SwiftUI
import CookingAppCore

/// Compact, non-blocking strip showing the partner's current step and connection status.
/// Carries its own tap gesture (that does nothing) purely to absorb taps — without it, a tap
/// here would fall through to StepView's full-screen "advance" gesture underneath and
/// accidentally skip the local user's own step.
struct PartnerStatusView: View {
    let session: CookingSessionViewModel

    var body: some View {
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

            // A small preview of what the partner is doing — enough to glance at, not enough
            // to compete with your own full-screen step for attention.
            if let partnerImage = session.partnerStep?.imageSystemName, session.partnerConnectionState == .connected {
                Image(systemName: partnerImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var partnerLabel: String {
        session.role == .personA ? "Partner (Person B)" : "Partner (Person A)"
    }

    private var dotColor: Color {
        switch session.partnerConnectionState {
        case .connected: return .green
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
            return session.partnerStep?.instruction ?? "Getting started…"
        default:
            return "Connecting…"
        }
    }
}
