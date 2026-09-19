import SwiftUI
import CookingAppCore

/// Shown once, the first time the app is ever opened — asks what to call you (so a partner in a
/// two-person session sees your actual name instead of a device hostname or "Person A/B") and how
/// comfortable you are in the kitchen. Stored in `@AppStorage("cookName")`/`@AppStorage("cookExpertise")`;
/// also reused as a standalone "change your experience level" sheet from `RecipeListView`, which
/// is why `name`/`onContinue` still work even when this view is shown a second time.
struct WelcomeNameView: View {
    @Binding var name: String
    @Binding var expertise: CookExpertise
    let onContinue: () -> Void

    @State private var draft = ""
    @State private var draftExpertise: CookExpertise = .intermediate
    @FocusState private var fieldFocused: Bool

    /// Reused later as a "change your experience level" sheet (see `RecipeListView`) rather than
    /// only ever showing once — a name already being set is what tells the two forms apart.
    private var isEditingExisting: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
        VStack(spacing: 24) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(isEditingExisting ? "Your Profile" : "Welcome!")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
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

            VStack(alignment: .leading, spacing: 6) {
                Text("How comfortable are you in the kitchen?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Cooking experience", selection: $draftExpertise) {
                    ForEach(CookExpertise.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("cookExpertisePicker")
            }
            .padding(.horizontal, 40)

            Text("Changes how much hand-holding cooking steps give you — you can change this anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Continue") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedDraft.isEmpty)
        }
        .padding()
        .padding(.top, 40)
        }
        .onAppear {
            draft = name
            draftExpertise = expertise
            // Only steal focus (and pop the keyboard) on the very first-ever launch, when
            // typing a name is the one thing to do here — reopened later purely to change the
            // experience level, auto-focusing would pop the keyboard right over the picker
            // below, making it look "stuck" (unreachable, not just unfocused) until you notice
            // you have to dismiss the keyboard first. See `isEditingExisting`.
            fieldFocused = !isEditingExisting && !UIAccessibility.isVoiceOverRunning
        }
    }

    private func save() {
        guard !trimmedDraft.isEmpty else { return }
        name = trimmedDraft
        expertise = draftExpertise
        onContinue()
    }
}
