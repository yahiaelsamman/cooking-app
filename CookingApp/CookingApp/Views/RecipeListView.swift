import SwiftUI
import SwiftData
import CookingAppCore

struct RecipeListView: View {
    @Environment(ActiveSessionStore.self) private var sessionStore
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @State private var path = NavigationPath()
    @AppStorage("cookName") private var cookName: String = ""
    @State private var showWelcomeName = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                List(recipes) { recipe in
                    Button {
                        path.append(Route.detail(recipe))
                    } label: {
                        RecipeRow(recipe: recipe)
                    }
                    .buttonStyle(.plain)
                }

                if sessionStore.hasActiveSession {
                    ResumeSessionButton {
                        if let session = sessionStore.currentSession {
                            path.append(Route.steps(session))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Recipes")
            .onAppear {
                // Requested once, right at app start — not the first time you happen to start a
                // timer — so the permission prompt doesn't ambush you mid-cook.
                NotificationScheduler.requestAuthorizationIfNeeded()
                if cookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    showWelcomeName = true
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .detail(let recipe):
                    RecipeDetailView(recipe: recipe, path: $path)
                case .peerConnection(let recipe):
                    PeerConnectionView(recipe: recipe, path: $path)
                case .steps(let session):
                    StepView(session: session, path: $path)
                }
            }
            .sheet(isPresented: $showWelcomeName) {
                WelcomeNameView(name: $cookName) {
                    showWelcomeName = false
                }
                .interactiveDismissDisabled()
            }
        }
    }
}

/// Bottom-right floating button that jumps straight back into whatever session is currently
/// active — skipping the recipe/connect flow entirely, which is what preserves Person A/B roles
/// on a two-person session: it re-enters the *same* `CookingSessionViewModel`, it never asks you
/// to choose Host or Join again.
private struct ResumeSessionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Resume Cooking", systemImage: "flame.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
                .shadow(radius: 4, y: 2)
        }
    }
}

private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RecipeThumbnailView(recipe: recipe)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(recipe.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    DifficultyStarsView(difficulty: recipe.difficulty)
                    if recipe.spiceLevel > 0 {
                        SpiceLevelView(spiceLevel: recipe.spiceLevel)
                    }
                    Label("\(recipe.soloCookTimeMinutes) min", systemImage: "clock.fill")
                    if recipe.supportsTwoPerson {
                        Label("Also for two", systemImage: "person.2.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

                if !recipe.dietaryTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(recipe.dietaryTags, id: \.self) { tag in
                            Label(tag.label, systemImage: tag.systemImage)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The small square photo in a recipe row. Deliberately *not* the gradient `PlaceholderPhotoView`
/// card treatment used at full hero size — that doesn't read well this small (see
/// `PlaceholderPhotoView`'s doc comment) — so a recipe without a real photo yet keeps the plain
/// SF-Symbol tile look it's always had, and only recipes with an approved `heroImageName` upgrade
/// to a real cropped photo.
private struct RecipeThumbnailView: View {
    let recipe: Recipe

    var body: some View {
        Group {
            if let heroImageName = recipe.heroImageName {
                Image(heroImageName)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: recipe.iconSystemName)
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.12))
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 1-3 filled-out-of-3 stars, used wherever a recipe's difficulty is shown.
struct DifficultyStarsView: View {
    let difficulty: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...3, id: \.self) { position in
                Image(systemName: position <= difficulty ? "star.fill" : "star")
            }
        }
    }
}

/// 1-3 filled-out-of-3 flames, used wherever a recipe's spice level is shown. Callers should
/// only show this when `spiceLevel > 0` — a recipe with no spice doesn't need an empty row of
/// outlined flames competing for attention with difficulty/cook-time.
struct SpiceLevelView: View {
    let spiceLevel: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...3, id: \.self) { position in
                Image(systemName: position <= spiceLevel ? "flame.fill" : "flame")
            }
        }
        .foregroundStyle(.red)
    }
}
