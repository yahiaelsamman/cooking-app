import SwiftUI
import SwiftData
import CookingAppCore

/// The three ways `RecipeListView` can order its rows. `.myOrder` is the only one that supports
/// drag-to-reorder (it's the only one backed by a field the user actually controls — the other
/// two are always freshly derived, so "reordering" them wouldn't mean anything durable).
private enum RecipeSortMode: String, CaseIterable, Identifiable {
    case myOrder = "My Order"
    case alphabetical = "A–Z"
    case topRated = "Top Rated"

    var id: String { rawValue }
}

struct RecipeListView: View {
    @Environment(ActiveSessionStore.self) private var sessionStore
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]
    @State private var path = NavigationPath()
    @AppStorage("cookName") private var cookName: String = ""
    @State private var showWelcomeName = false
    @State private var sortMode: RecipeSortMode = .myOrder
    @State private var showFavoritesOnly = false
    @State private var showAddRecipe = false

    private var displayedRecipes: [Recipe] {
        let base = showFavoritesOnly ? recipes.filter(\.isFavorite) : recipes
        switch sortMode {
        case .myOrder:
            return base.sorted { $0.sortOrder < $1.sortOrder }
        case .alphabetical:
            return base.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .topRated:
            return base.sorted { (lhs, rhs) in
                let l = lhs.personalRating ?? -1
                let r = rhs.personalRating ?? -1
                return l == r ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending : l > r
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                List {
                    if sortMode == .myOrder {
                        ForEach(displayedRecipes) { recipe in
                            recipeRow(for: recipe)
                        }
                        .onMove(perform: moveRecipes)
                    } else {
                        ForEach(displayedRecipes) { recipe in
                            recipeRow(for: recipe)
                        }
                    }
                }
                .environment(\.editMode, .constant(sortMode == .myOrder ? .active : .inactive))

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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFavoritesOnly.toggle()
                        if showFavoritesOnly && sortMode == .myOrder {
                            // Dragging within a filtered subset would silently scramble the full
                            // sortOrder sequence for hidden recipes — simplest to just leave
                            // reorder mode while the filter narrows what's on screen.
                            sortMode = .alphabetical
                        }
                    } label: {
                        Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                            .foregroundStyle(.pink)
                    }
                    .accessibilityLabel(showFavoritesOnly ? "Show all recipes" : "Show favorites only")
                    .accessibilityIdentifier("favoritesFilterButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(RecipeSortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddRecipe = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Recipe")
                    .accessibilityIdentifier("addRecipeButton")
                }
            }
            .onAppear {
                // The system notification permission dialog can't be reliably dismissed from
                // XCUITest, so UI tests skip requesting it entirely — CookingAppUITests always
                // launches with this flag.
                if !ProcessInfo.processInfo.arguments.contains("-UITesting") {
                    // Requested once, right at app start — not the first time you happen to
                    // start a timer — so the permission prompt doesn't ambush you mid-cook.
                    NotificationScheduler.requestAuthorizationIfNeeded()
                }
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
            .sheet(isPresented: $showAddRecipe) {
                RecipeEditorView()
            }
        }
    }

    @ViewBuilder
    private func recipeRow(for recipe: Recipe) -> some View {
        Button {
            path.append(Route.detail(recipe))
        } label: {
            RecipeRow(recipe: recipe)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recipeRow_\(recipe.title)")
        .swipeActions(edge: .leading) {
            Button {
                recipe.isFavorite.toggle()
                try? modelContext.save()
            } label: {
                Label(recipe.isFavorite ? "Unfavorite" : "Favorite", systemImage: recipe.isFavorite ? "heart.slash" : "heart")
            }
            .accessibilityIdentifier("swipeFavoriteButton_\(recipe.title)")
            .tint(.pink)
        }
    }

    /// Only reachable in `.myOrder` mode (see body) with the favorites filter off, so
    /// `displayedRecipes` here is exactly `recipes` sorted by `sortOrder` — safe to rewrite every
    /// recipe's `sortOrder` to match the new full ordering.
    private func moveRecipes(from source: IndexSet, to destination: Int) {
        var ordered = displayedRecipes
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, recipe) in ordered.enumerated() {
            recipe.sortOrder = index
        }
        try? modelContext.save()
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
                HStack(spacing: 6) {
                    Text(recipe.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
                    }
                }
                Text(recipe.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if recipe.personalRating != nil || recipe.timesCooked > 0 {
                    HStack(spacing: 8) {
                        if recipe.personalRating != nil {
                            StarRatingView(rating: recipe.personalRating, interactive: false)
                        }
                        if recipe.timesCooked > 0 {
                            Label("Cooked \(recipe.timesCooked)×", systemImage: "checkmark.circle.fill")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 1)
                }

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
