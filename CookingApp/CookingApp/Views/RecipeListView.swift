import SwiftUI
import CookingAppCore

struct RecipeListView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List(SampleRecipes.all) { recipe in
                Button {
                    path.append(Route.detail(recipe))
                } label: {
                    RecipeRow(recipe: recipe)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Recipes")
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
                    Label("\(recipe.cookTimeMinutes) min", systemImage: "clock.fill")
                    if recipe.isTwoPerson {
                        Label("Two-person", systemImage: "person.2.fill")
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
