import SwiftUI
import CookingAppCore

/// Shown the first time you tap into a recipe — an overview (ingredients + a read-through of
/// every step) so you can decide whether to actually cook it before committing to "Start
/// Cooking" and losing the wall-of-text view in favor of the one-step-at-a-time screen.
struct RecipeDetailView: View {
    let recipe: Recipe
    @Binding var path: NavigationPath

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                metadataRow

                if !recipe.dietaryTags.isEmpty {
                    dietaryTagsRow
                }

                startCookingButton

                ingredientsSection

                stepsOverviewSection
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: recipe.iconSystemName)
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .frame(width: 120, height: 120)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                .frame(maxWidth: .infinity)

            Text(recipe.title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(recipe.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                DifficultyStarsView(difficulty: recipe.difficulty)
                Text("Difficulty").font(.caption2).foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                Label("\(recipe.cookTimeMinutes) min", systemImage: "clock.fill")
                Text("Cook Time").font(.caption2).foregroundStyle(.secondary)
            }
            if let servings = recipe.servings {
                VStack(spacing: 4) {
                    Label("\(servings)", systemImage: "person.fill")
                    Text("Servings").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if recipe.isTwoPerson {
                VStack(spacing: 4) {
                    Label("2", systemImage: "person.2.fill")
                        .foregroundStyle(.blue)
                    Text("Two-Person").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity)
    }

    private var dietaryTagsRow: some View {
        HStack(spacing: 8) {
            ForEach(recipe.dietaryTags, id: \.self) { tag in
                Label(tag.label, systemImage: tag.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var startCookingButton: some View {
        Button {
            startCooking()
        } label: {
            Text("Start Cooking")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ingredients").font(.title3.bold())
            ForEach(recipe.ingredients) { ingredient in
                HStack {
                    Text(ingredient.name)
                    Spacer()
                    Text(ingredient.amount)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
    }

    private var stepsOverviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Steps").font(.title3.bold())

            if recipe.isTwoPerson {
                stepsGroup(title: "Together", steps: recipe.steps.filter { $0.assignee == .shared }.sorted { $0.order < $1.order })
                stepsGroup(title: "Person A", steps: recipe.steps.filter { $0.assignee == .personA }.sorted { $0.order < $1.order })
                stepsGroup(title: "Person B", steps: recipe.steps.filter { $0.assignee == .personB }.sorted { $0.order < $1.order })
            } else {
                stepsGroup(title: nil, steps: recipe.track(for: nil))
            }
        }
    }

    @ViewBuilder
    private func stepsGroup(title: String?, steps: [RecipeStep]) -> some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                        Text(step.instruction)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func startCooking() {
        if recipe.isTwoPerson {
            path.append(Route.peerConnection(recipe))
        } else {
            let session = CookingSessionViewModel(recipe: recipe)
            path.append(Route.steps(session))
        }
    }
}
