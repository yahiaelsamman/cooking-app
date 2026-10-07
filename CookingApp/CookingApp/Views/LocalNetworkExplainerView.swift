import SwiftUI

/// Shown once, right before the first Host/Join starts the service that makes iOS show its
/// "find devices on your local network" permission prompt — so the system dialog isn't a surprise.
/// `PeerConnectionView` remembers the acknowledgement in `UserDefaults`.
struct LocalNetworkExplainerView: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Find your partner nearby")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("To cook together, the two phones find each other over your local network or Bluetooth. iOS will ask to let Cooking App find devices on your local network; tap Allow so your partner shows up.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Nothing leaves your phones: no accounts, no servers.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("localNetworkContinueButton")
            Button("Not Now", action: onCancel)
                .accessibilityIdentifier("localNetworkNotNowButton")
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .presentationDetents([.medium, .large])
    }
}
