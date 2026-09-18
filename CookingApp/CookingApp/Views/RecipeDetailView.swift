import SwiftUI
import SwiftData
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
    @State private var showEditRecipe = false
    /// Starts at the recipe's own `servings` (or 1 for a recipe that doesn't declare one — the
    /// scaling controls simply aren't shown in that case, see `ingredientsSection`). Purely
    /// ephemeral view state, the same as `mode` above: it resets to the recipe's base serving
    /// count every time this screen is opened rather than being remembered, since it describes
    /// "how many people am I cooking for right now," not a durable preference about the recipe
    /// itself.
    @State private var targetServings: Int
    /// Briefly swaps the "Add to Shopping List" toolbar icon to a checkmark after tapping it —
    /// the action itself has no other visible effect on this screen (the list it updates is a
    /// separate sheet), so without this there'd be no confirmation the tap did anything at all.
    @State private var justAddedToShoppingList = false
    @AppStorage("hasSeenRecipeDetailTour") private var hasSeenRecipeDetailTour = false
    @State private var tour = AppTour()

    init(recipe: Recipe, path: Binding<NavigationPath>) {
        self.recipe = recipe
        self._path = path
        _targetServings = State(initialValue: recipe.servings ?? 1)
    }

    /// Built fresh each time the tour begins, since which steps even apply depends on this
    /// particular recipe — a solo-only recipe skips the mode-picker step, one with no declared
    /// `servings` skips the scaling-stepper step, same "don't explain a control that isn't even
    /// on screen" stance the screen itself already takes (see `modePicker`/`servingsStepper`).
    private var recipeDetailTourSteps: [TourStep] {
        var steps = [
            TourStep(
                id: "intro",
                title: "Everything about this recipe",
                message: "Scroll down to see the ingredients and every step written out — read through as much as you like before you start."
            ),
            TourStep(
                target: "detailFavoriteButton",
                title: "Favorites",
                message: "Tap the heart to save this recipe as a favorite."
            ),
            TourStep(
                target: "addToShoppingListButton",
                title: "Shopping List",
                message: "Tap the cart to add these ingredients to your shopping list."
            )
        ]
        if recipe.supportsTwoPerson {
            steps.append(
                TourStep(
                    target: "modePicker",
                    title: "Cooking Together",
                    message: "This recipe can be split between two phones. Switch here to cook it with a partner."
                )
            )
        }
        if recipe.servings != nil {
            steps.append(
                TourStep(
                    target: "servingsStepper",
                    title: "Servings",
                    message: "Tap + or – to scale the ingredient amounts for more or fewer people."
                )
            )
        }
        steps.append(
            TourStep(
                target: "startCookingButton",
                title: "Start Cooking",
                message: "When you're ready, tap Start Cooking to begin, one step at a time."
            )
        )
        return steps
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    metadataRow

                    if !recipe.dietaryTags.isEmpty {
                        dietaryTagsRow
                    }

                    // Only offered when the recipe actually has a curated two-person split —
                    // there's no generic "mirror" fallback, so a recipe without one simply
                    // doesn't show this at all rather than offering a toggle that leads nowhere
                    // useful.
                    if recipe.supportsTwoPerson {
                        modePicker
                    }

                    startCookingButton

                    MyNotesSection(recipe: recipe)

                    ingredientsSection

                    stepsOverviewSection
                }
                .padding()
            }
            .onChange(of: tour.currentStep?.targetID) { _, targetID in
                guard let targetID else { return }
                withAnimation {
                    scrollProxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
        .onAppear {
            if !hasSeenRecipeDetailTour {
                // Marked seen the moment the tour begins, not when every highlighted control has
                // actually been tapped — tapping "Start Cooking" without first tapping the
                // favorite/cart/servings controls (the natural thing to do) would otherwise leave
                // this stuck mid-tour forever, replaying from step 0 on every future recipe.
                hasSeenRecipeDetailTour = true
                tour.begin(recipeDetailTourSteps)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if recipe.isUserCreated {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEditRecipe = true }
                        .accessibilityIdentifier("editRecipeButton")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    recipe.isFavorite.toggle()
                    try? modelContext.save()
                    tour.notify("detailFavoriteButton")
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(.pink)
                }
                .accessibilityLabel(recipe.isFavorite ? "Remove from favorites" : "Add to favorites")
                .accessibilityIdentifier("detailFavoriteButton")
                .tourAnchor("detailFavoriteButton")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addIngredientsToShoppingList()
                    tour.notify("addToShoppingListButton")
                } label: {
                    Image(systemName: justAddedToShoppingList ? "checkmark.circle.fill" : "cart.badge.plus")
                        .foregroundStyle(justAddedToShoppingList ? .green : Color.accentColor)
                }
                .accessibilityLabel("Add to Shopping List")
                .accessibilityIdentifier("addToShoppingListButton")
                .tourAnchor("addToShoppingListButton")
            }
        }
        .overlayPreferenceValue(TourAnchorPreferenceKey.self) { anchors in
            TourSpotlight(tour: tour, anchors: anchors)
        }
        .sheet(isPresented: $showEditRecipe) {
            RecipeEditorView(existingRecipe: recipe, onDelete: deleteRecipeAndPopBack)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            // Fills the full content width (this screen scrolls, so there's no "must fit on one
            // screen" ceiling the way there is in StepView) — legible at a glance is the point,
            // and a tall, wide hero reads far better than the old fixed 260x160 crop.
            RecipeHeroImageView(recipe: recipe)
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipped()

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
            if recipe.servings != nil {
                VStack(spacing: 4) {
                    Label("\(targetServings)", systemImage: "person.fill")
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
        .id("modePicker")
        .tourAnchor("modePicker")
        .onChange(of: mode) { _, _ in
            tour.notify("modePicker")
        }
    }

    private var startCookingButton: some View {
        Button {
            startCooking()
            tour.notify("startCookingButton")
        } label: {
            Text("Start Cooking")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .id("startCookingButton")
        .tourAnchor("startCookingButton")
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ingredients").font(.title3.bold())
                Spacer()
                // Only offered when the recipe declares a base serving count to scale relative
                // to — same "don't show a control that has nothing sensible to do" stance as
                // `modePicker` above for two-person mode.
                if recipe.servings != nil {
                    servingsStepper
                }
            }
            ForEach(recipe.ingredients) { ingredient in
                HStack {
                    Text(ingredient.name)
                    Spacer()
                    Text(ingredient.scaledAmount(by: servingsScaleFactor))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("ingredientAmount_\(ingredient.name)")
                }
                .font(.subheadline)
            }
        }
    }

    private var servingsStepper: some View {
        HStack(spacing: 10) {
            Button {
                targetServings = max(1, targetServings - 1)
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .accessibilityLabel("Fewer servings")
            .accessibilityIdentifier("decreaseServingsButton")

            Text("\(targetServings) \(targetServings == 1 ? "serving" : "servings")")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .frame(minWidth: 70)

            Button {
                targetServings = min(20, targetServings + 1)
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .accessibilityLabel("More servings")
            .accessibilityIdentifier("increaseServingsButton")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .id("servingsStepper")
        .tourAnchor("servingsStepper")
        .onChange(of: targetServings) { _, _ in
            tour.notify("servingsStepper")
        }
    }

    /// 1 (no change) unless the recipe declares a base `servings` count — an ingredient's amount
    /// is only ever scaled relative to that, never guessed at.
    private var servingsScaleFactor: Double {
        guard let baseServings = recipe.servings, baseServings > 0 else { return 1 }
        return Double(targetServings) / Double(baseServings)
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

    /// Navigates away *before* actually deleting — this screen holds a live `@Bindable` reference
    /// to `recipe`, so deleting it while still on screen (even mid-dismiss-animation, which is
    /// what a naive `onDismiss`-triggered delete would do) risks this view's body reading a model
    /// SwiftData has already faulted out from under it. Resetting `path` first means this view is
    /// no longer part of the active navigation stack by the time the delete actually happens.
    private func deleteRecipeAndPopBack() {
        path = NavigationPath()
        modelContext.delete(recipe)
        try? modelContext.save()
    }

    /// Adds this recipe's ingredients — at whatever serving count the stepper is currently set
    /// to, see `servingsScaleFactor` — to the shared shopping list. `ShoppingListItem.itemsToAdd`
    /// does the actual dedup-against-what's-already-there logic; this just fetches the current
    /// list to hand it and persists whatever comes back.
    private func addIngredientsToShoppingList() {
        let existingItems = (try? modelContext.fetch(FetchDescriptor<ShoppingListItem>())) ?? []
        let newItems = ShoppingListItem.itemsToAdd(for: recipe, scaleFactor: servingsScaleFactor, existingItems: existingItems)
        for item in newItems { modelContext.insert(item) }
        try? modelContext.save()

        justAddedToShoppingList = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            justAddedToShoppingList = false
        }
    }
}

/// Rating, cook history, and the free-text notes field — split out from `RecipeDetailView` so
/// typing in the notes `TextEditor` only re-evaluates this small view's body, not the whole
/// screen (hero image, metadata, ingredients, full step overview all live in the parent and don't
/// read `personalNotes`). Also debounces the save itself: writing to `modelContext` on every
/// keystroke was a synchronous disk write on the main thread per character typed.
private struct MyNotesSection: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var modelContext

    var body: some View {
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
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Notes")
            .padding(6)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            // Debounced rather than saved on every keystroke: `.task(id:)` cancels its previous
            // Task the instant `personalNotes` changes again (SwiftUI's own behavior for a
            // changed task id), so only the save that survives 600ms of no further typing ever
            // actually reaches disk — one write per pause instead of one per character. The
            // `.onDisappear` save below is the safety net for "typed something, then immediately
            // left the screen before the debounce fired."
            .task(id: recipe.personalNotes) {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                try? modelContext.save()
            }
        }
        .onDisappear {
            try? modelContext.save()
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
}
