import SwiftUI

/// App name/version, a plain-language privacy statement, and credits. Reached from the info button
/// in `RecipeListView`'s toolbar.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private static let repoURL = URL(string: "https://github.com/yahiaelsamman/cooking-app")!
    private static let pexelsLicenseURL = URL(string: "https://www.pexels.com/license/")!

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        Text("Cooking App")
                            .font(.title2.bold())
                        Text(versionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("aboutVersion")
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .listRowBackground(Color.clear)
                }

                Section("Privacy") {
                    Text("Your recipes, notes, ratings and shopping list stay on this device. There are no accounts and no analytics. The only network use is local, peer-to-peer syncing with a partner you choose for two-person cooking; nothing is sent to a server.")
                        .font(.callout)
                        .accessibilityIdentifier("aboutPrivacyText")
                }

                Section("Credits") {
                    Text("Hero photos for Seared Steak, Weeknight Pasta, Tomato Soup, Homemade Pizza and Taco Night are free stock photos from Pexels. Thank you to the photographers.")
                        .font(.callout)
                    Link("Pexels license", destination: Self.pexelsLicenseURL)
                    Text("The step-by-step illustrations for Scrambled Eggs, Avocado Toast and Grilled Cheese are AI-generated.")
                        .font(.callout)
                }

                Section("Open source") {
                    Text("Released under the MIT license.")
                        .font(.callout)
                    Link("Source code on GitHub", destination: Self.repoURL)
                        .accessibilityIdentifier("aboutRepoLink")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("aboutDoneButton")
                }
            }
        }
    }
}
