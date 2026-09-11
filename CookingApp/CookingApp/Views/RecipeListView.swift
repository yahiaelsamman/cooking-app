import SwiftUI
import CookingAppCore

struct RecipeListView: View {
    @Environment(ActiveSessionStore.self) private var sessionStore
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                List(SampleRecipes.all) { recipe in
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
            Image(systemName: recipe.iconSystemName)
                .font(.system(size: 30))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

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
