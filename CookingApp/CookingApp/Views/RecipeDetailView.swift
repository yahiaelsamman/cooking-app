import SwiftUI
import CookingAppCore

private enum CookingMode: String, CaseIterable {
    case solo = "Solo"
    case twoPerson = "Two-Person"
}

/// Shown the first time you tap into a recipe — an overview (ingredients + a read-through of
/// every step) so you can decide whether to actually cook it before committing to "Start
/// Cooking" and losing the wall-of-text view in favor of the one-step-at-a-time screen.
struct RecipeDetailView: View {
    let recipe: Recipe
    @Binding var path: NavigationPath
    @Environment(ActiveSessionStore.self) private var sessionStore

    @State private var mode: CookingMode = .solo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                metadataRow

                if !recipe.dietaryTags.isEmpty {
                    dietaryTagsRow
                }

                modePicker

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
            if recipe.spiceLevel > 0 {
                VStack(spacing: 4) {
                    SpiceLevelView(spiceLevel: recipe.spiceLevel)
                    Text("Spice").font(.caption2).foregroundStyle(.secondary)
                }
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

    /// Every recipe can be cooked solo or with a partner — two-person mode divides labor when
    /// there's a curated split, and otherwise mirrors the full recipe to both phones so you can
    /// still cook together side by side.
    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Cooking mode", selection: $mode) {
                ForEach(CookingMode.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if mode == .twoPerson {
                Text(recipe.hasCuratedSplit
                     ? "Splits into two tracks — you and your partner each handle half, with a few steps together."
                     : "No task split for this one — you'll each cook the full recipe on your own phone, synced together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

            if recipe.hasCuratedSplit {
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
        if mode == .twoPerson {
            path.append(Route.peerConnection(recipe))
        } else {
            let session = CookingSessionViewModel(recipe: recipe)
            sessionStore.setActive(session)
            path.append(Route.steps(session))
        }
    }
}
