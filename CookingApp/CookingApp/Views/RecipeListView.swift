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
    @State private var path: [Route] = []
    @AppStorage("cookName") private var cookName: String = ""
    @AppStorage("cookExpertise") private var cookExpertiseRaw: String = CookExpertise.intermediate.rawValue
    @State private var showWelcomeName = false
    @AppStorage("hasSeenRecipeListTour") private var hasSeenRecipeListTour = false
    @State private var tour = AppTour()
    @State private var sortMode: RecipeSortMode = .alphabetical
    @State private var showFavoritesOnly = false
    @State private var showAddRecipe = false
    @State private var showShoppingList = false
    @State private var searchText = ""
    @State private var selectedDietaryTags: Set<DietaryTag> = []

    /// Reordering must never run against a favorites-, search-, or dietary-filtered subset — that
    /// would rewrite `sortOrder` 0..<k only across the visible rows, colliding with and corrupting
    /// the `sortOrder`s of every hidden recipe. Computed reactively (rather than only checked at
    /// the specific places each piece of filter state changes) so it stays correct no matter which
    /// control — the favorites button, the sort Picker, search, or a dietary chip — is what brings
    /// any of these conditions true at once.
    private var cookExpertiseBinding: Binding<CookExpertise> {
        Binding(
            get: { CookExpertise(rawValue: cookExpertiseRaw) ?? .intermediate },
            set: { cookExpertiseRaw = $0.rawValue }
        )
    }

    private var canReorder: Bool {
        sortMode == .myOrder && !showFavoritesOnly && searchText.isEmpty && selectedDietaryTags.isEmpty
    }

    /// Built fresh each time the tour begins, since the last step needs to point at whichever
    /// recipe is actually first on screen right now (alphabetical by default) — not a hardcoded
    /// title that might not even be in `displayedRecipes` once filters or sort change.
    private var recipeListTourSteps: [TourStep] {
        var steps = [
            TourStep(
                id: "intro",
                title: "Welcome to your recipes",
                message: "This app walks you through cooking one step at a time, instead of one big page of text to keep track of."
            ),
            TourStep(
                target: "favoritesFilterButton",
                title: "Favorites",
                message: "Use the Show favorites only button to see just the recipes you've favorited."
            ),
            TourStep(
                target: "shoppingListButton",
                title: "Shopping List",
                message: "Use the Shopping List button to see everything you've added."
            ),
            TourStep(
                target: "cookingProfileButton",
                title: "Your Profile",
                message: "Use the Your Profile button anytime to change your name or how comfortable you are in the kitchen."
            ),
            TourStep(
                id: "search",
                title: "Search",
                message: "Type here to find a recipe or an ingredient by name."
            ),
            TourStep(
                target: "addRecipeButton",
                title: "Write Your Own",
                message: "Use the Add Recipe button to add one of your own recipes."
            )
        ]
        if let firstRecipe = displayedRecipes.first {
            steps.append(
                TourStep(
                    target: "recipeRow_\(firstRecipe.title)",
                    title: "Open a Recipe",
                    message: "Tap any recipe to see what's in it and start cooking."
                )
            )
        }
        return steps
    }

    private var displayedRecipes: [Recipe] {
        let favorited = showFavoritesOnly ? recipes.filter(\.isFavorite) : recipes
        let searched = searchText.isEmpty ? favorited : favorited.filter { $0.matchesSearch(searchText) }
        let base = selectedDietaryTags.isEmpty ? searched : searched.filter { $0.matchesDietaryFilter(selectedDietaryTags) }
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
                    if canReorder {
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
                // Explicit rather than relying on `.automatic`: this list uses a custom card
                // treatment per row (see `recipeRow`), and `.automatic` risks the system's
                // grouped/inset chrome fighting that on some size classes.
                .listStyle(.plain)
                .environment(\.editMode, .constant(canReorder ? .active : .inactive))
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        // At the top, not floating at the bottom: on iOS 26 the search field sits
                        // along the bottom edge and covered the old bottom-right button entirely.
                        if let session = sessionStore.currentSession {
                            ResumeSessionButton(session: session) {
                                path.append(.steps(session))
                            }
                        }
                        dietaryFilterChips
                    }
                }
            }
            .navigationTitle("Recipes")
            .searchable(text: $searchText, prompt: "Search recipes or ingredients")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFavoritesOnly.toggle()
                        tour.notify("favoritesFilterButton")
                    } label: {
                        Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                            .foregroundStyle(.pink)
                    }
                    .accessibilityLabel(showFavoritesOnly ? "Show all recipes" : "Show favorites only")
                    .accessibilityIdentifier("favoritesFilterButton")
                    .tourAnchor("favoritesFilterButton")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showShoppingList = true
                        tour.notify("shoppingListButton")
                    } label: {
                        Image(systemName: "cart")
                    }
                    .accessibilityLabel("Shopping List")
                    .accessibilityIdentifier("shoppingListButton")
                    .tourAnchor("shoppingListButton")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showWelcomeName = true
                        tour.notify("cookingProfileButton")
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Your Profile")
                    .accessibilityIdentifier("cookingProfileButton")
                    .tourAnchor("cookingProfileButton")
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
                        tour.notify("addRecipeButton")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Recipe")
                    .accessibilityIdentifier("addRecipeButton")
                    .tourAnchor("addRecipeButton")
                }
            }
            .overlayPreferenceValue(TourAnchorPreferenceKey.self) { anchors in
                TourSpotlight(tour: tour, anchors: anchors)
            }
            .onAppear {
                if cookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    showWelcomeName = true
                } else if !hasSeenRecipeListTour {
                    // Marked seen the moment the tour begins, not when every highlighted control
                    // has actually been tapped — tapping straight into a recipe (the natural
                    // thing to do) would otherwise leave this stuck mid-tour forever, replaying
                    // from step 0 on every future visit to this screen.
                    hasSeenRecipeListTour = true
                    tour.begin(recipeListTourSteps)
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
                WelcomeNameView(name: $cookName, expertise: cookExpertiseBinding) {
                    showWelcomeName = false
                    if !hasSeenRecipeListTour {
                        hasSeenRecipeListTour = true
                        tour.begin(recipeListTourSteps)
                    }
                }
                // Only blocks dismissal on first run, when a name hasn't been set yet — reopened
                // later purely to change the experience level, it should dismiss like any other
                // sheet.
                .interactiveDismissDisabled(cookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .sheet(isPresented: $showAddRecipe) {
                RecipeEditorView()
            }
            .sheet(isPresented: $showShoppingList) {
                ShoppingListView()
            }
        }
    }

    /// AND-filter chips (see `Recipe.matchesDietaryFilter`) — every `DietaryTag` is always
    /// offered regardless of the current result set, the same as any standard filter UI; it's
    /// not narrowed to only tags some visible recipe currently has.
    private var dietaryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DietaryTag.allCases, id: \.self) { tag in
                    let isSelected = selectedDietaryTags.contains(tag)
                    Button {
                        if isSelected {
                            selectedDietaryTags.remove(tag)
                        } else {
                            selectedDietaryTags.insert(tag)
                        }
                    } label: {
                        Label(tag.label, systemImage: tag.systemImage)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.green : Color.green.opacity(0.12), in: Capsule())
                            .foregroundStyle(isSelected ? .white : .green)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityIdentifier("dietaryFilterChip_\(tag.rawValue)")
                }
            }
            .padding(.horizontal)
            // 44pt chip hit areas already provide the vertical breathing room.
        }
        .background(.bar)
    }

    @ViewBuilder
    private func recipeRow(for recipe: Recipe) -> some View {
        Button {
            path.append(.detail(recipe))
            tour.notify("recipeRow_\(recipe.title)")
        } label: {
            RecipeRow(recipe: recipe)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recipeRow_\(recipe.title)")
        .tourAnchor("recipeRow_\(recipe.title)")
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .swipeActions(edge: .leading) {
            Button {
                recipe.isFavorite.toggle()
                try? modelContext.save()
            } label: {
                Label(recipe.isFavorite ? "Remove from favorites" : "Add to favorites", systemImage: recipe.isFavorite ? "heart.slash" : "heart")
            }
            .accessibilityIdentifier("swipeFavoriteButton_\(recipe.title)")
            .tint(.pink)
        }
    }

    /// Only wired to `.onMove` when `canReorder` is true (see body), which guarantees the
    /// favorites filter, search, and dietary filter are all off — so `displayedRecipes` here is
    /// exactly `recipes` sorted by `sortOrder`, safe to rewrite in full to match the new ordering.
    private func moveRecipes(from source: IndexSet, to destination: Int) {
        var ordered = displayedRecipes
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, recipe) in ordered.enumerated() {
            recipe.sortOrder = index
        }
        try? modelContext.save()
    }
}

/// Full-width row at the top of the list that jumps straight back into whatever session is
/// currently active — skipping the recipe/connect flow entirely, which is what preserves Person A/B
/// roles on a two-person session: it re-enters the *same* `CookingSessionViewModel`, it never asks
/// you to choose Host or Join again. Names the recipe and step so it's clear what you'd resume.
private struct ResumeSessionButton: View {
    let session: CookingSessionViewModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume Cooking")
                        .font(.headline)
                    Text("\(session.recipe.title) · \(session.progressText)")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityLabel("Resume cooking \(session.recipe.title)")
        .accessibilityValue(session.progressText)
    }
}

/// One recipe as a big-image card: a full-width photo (or the `PlaceholderPhotoView` gradient
/// card when there's no `heroImageName` yet — sized generously via `RecipeHeroImageView`, which
/// already does that real-photo-or-placeholder fallback) on top, everything else underneath.
/// Replaced the old small-leading-thumbnail row layout — a 52pt square thumbnail didn't do
/// justice to real recipe photos/illustrations, and this app is squarely about the images now.
private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RecipeHeroImageView(recipe: recipe)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(recipe.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
                            .accessibilityLabel("Favorite")
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
                                .accessibilityLabel(recipe.timesCooked == 1 ? "Cooked once" : "Cooked \(recipe.timesCooked) times")
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
                        .accessibilityLabel(recipe.soloCookTimeMinutes == 1 ? "1 minute" : "\(recipe.soloCookTimeMinutes) minutes")
                    if recipe.supportsTwoPerson {
                        Label("Also for two", systemImage: "person.2.fill")
                            .accessibilityLabel("Also works for two people")
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
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        // Without this, VoiceOver focuses each title/badge/label fragment separately — combining
        // stitches them into one sentence per row, reusing the labels DifficultyStarsView/
        // SpiceLevelView/StarRatingView already provide for their own pieces.
        .accessibilityElement(children: .combine)
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
        // Otherwise VoiceOver reads 3 indistinguishable "star"/"star fill" images with no
        // indication of what they're rating.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Difficulty: \(difficulty) out of 3")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spice level: \(spiceLevel) out of 3")
    }
}
