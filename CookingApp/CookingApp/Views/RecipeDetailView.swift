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
    @Bindable var recipe: Recipe
    @Binding var path: NavigationPath
    @Environment(ActiveSessionStore.self) private var sessionStore
    @Environment(\.modelContext) private var modelContext

    @State private var mode: CookingMode = .solo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                metadataRow

                if !recipe.dietaryTags.isEmpty {
                    dietaryTagsRow
                }

                // Only offered when the recipe actually has a curated two-person split — there's
                // no generic "mirror" fallback, so a recipe without one simply doesn't show this
                // at all rather than offering a toggle that leads nowhere useful.
                if recipe.supportsTwoPerson {
                    modePicker
                }

                startCookingButton

                myNotesSection

                ingredientsSection

                stepsOverviewSection
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    recipe.isFavorite.toggle()
                    try? modelContext.save()
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(.pink)
                }
                .accessibilityLabel(recipe.isFavorite ? "Remove from favorites" : "Add to favorites")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            RecipeHeroImageView(recipe: recipe)
                .frame(width: 260, height: 160)
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
                Label("\(recipe.cookTimeMinutes(forTwoPerson: mode == .twoPerson)) min", systemImage: "clock.fill")
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
        .animation(.default, value: mode)
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

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Cooking mode", selection: $mode) {
                ForEach(CookingMode.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if mode == .twoPerson {
                Text("Splits into two tracks — you and your partner each handle half, with a few steps together.")
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

    private var myNotesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Notes").font(.title3.bold())

            HStack {
                Text("Rating").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                StarRatingView(rating: recipe.personalRating) { newValue in
                    recipe.personalRating = newValue
                    try? modelContext.save()
                }
            }

            HStack {
                Text("Cooked").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(cookedSummary)
                    .font(.subheadline.weight(.medium))
            }

            TextEditor(text: Binding(
                get: { recipe.personalNotes },
                set: { recipe.personalNotes = $0 }
            ))
            .frame(minHeight: 80)
            .overlay(alignment: .topLeading) {
                if recipe.personalNotes.isEmpty {
                    Text("What did you change? How did it turn out?")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(6)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .onChange(of: recipe.personalNotes) { _, _ in
                try? modelContext.save()
            }
        }
    }

    private var cookedSummary: String {
        guard recipe.timesCooked > 0 else { return "Not yet" }
        let times = recipe.timesCooked == 1 ? "1 time" : "\(recipe.timesCooked) times"
        if let lastCookedDate = recipe.lastCookedDate {
            return "\(times), last on \(lastCookedDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return times
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

            if mode == .twoPerson, let twoPersonSteps = recipe.twoPersonSteps {
                stepsGroup(title: "Together", steps: twoPersonSteps.filter { $0.assignee == .shared }.sorted { $0.order < $1.order })
                stepsGroup(title: "Person A", steps: twoPersonSteps.filter { $0.assignee == .personA }.sorted { $0.order < $1.order })
                stepsGroup(title: "Person B", steps: twoPersonSteps.filter { $0.assignee == .personB }.sorted { $0.order < $1.order })
            } else {
                stepsGroup(title: nil, steps: recipe.soloSteps.sorted { $0.order < $1.order })
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
