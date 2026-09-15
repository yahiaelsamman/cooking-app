import SwiftUI

/// Shown once, the first time the app is ever opened — asks what to call you so a partner in a
/// two-person session sees your actual name instead of a device hostname or "Person A/B." Stored
/// in `@AppStorage("cookName")` and reused for every future two-person session.
struct WelcomeNameView: View {
    @Binding var name: String
    let onContinue: () -> Void

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Welcome!")
                    .font(.title.bold())
                Text("What should we call you?")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            TextField("Your name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .padding(.horizontal, 40)
                .submitLabel(.done)
                .onSubmit(save)
                .accessibilityIdentifier("welcomeNameField")

            Text("Used so a cooking partner sees your name, not your device's.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Continue") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedDraft.isEmpty)

            Spacer()
            Spacer()
        }
        .padding()
        .onAppear { fieldFocused = true }
    }

    private func save() {
        guard !trimmedDraft.isEmpty else { return }
        name = trimmedDraft
        onContinue()
    }
}
