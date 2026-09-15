import SwiftUI
import SwiftData
import CookingAppCore

/// Add or edit a user-created recipe. Shared between both flows — `existingRecipe == nil` means
/// "creating new," anything else means "editing that recipe in place."
///
/// Deliberately scoped to solo-only, single-track recipes: no two-person split editor. Curated
/// two-person splits are hand-authored content dividing real labor between two people (see
/// `SampleRecipes.swift`'s existing recipes for what that looks like) — generating a plausible
/// split from a solo step list isn't something this form attempts; a recipe created here simply
/// doesn't support two-person mode, the same as any of the 11 solo-only bundled recipes.
///
/// Editing and deleting are both restricted to `recipe.isUserCreated` — see `Recipe.isUserCreated`
/// and `RecipeSeeder`'s doc comments for why a bundled recipe's authored content and its
/// deletability are both out of scope for now.
struct RecipeEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allRecipes: [Recipe]

    /// `nil` when creating a brand-new recipe.
    let existingRecipe: Recipe?
    /// Called instead of this view deleting `existingRecipe` itself, so the presenting screen can
    /// pop away from it *before* it's actually removed from the store — see the call site in
    /// `RecipeDetailView` for why: that screen holds a live `@Bindable` reference to the same
    /// recipe, and deleting out from under it while it's still on screen (even mid-dismiss-
    /// animation) risks reading a model SwiftData has already faulted out.
    var onDelete: (() -> Void)? = nil

    @State private var title: String
    @State private var summary: String
    @State private var servingsText: String
    @State private var difficulty: Int
    @State private var spiceLevel: Int
    @State private var soloCookTimeText: String
    @State private var dietaryTags: Set<DietaryTag>
    @State private var ingredients: [Ingredient]
    @State private var steps: [RecipeStep]
    @State private var showDeleteConfirm = false

    init(existingRecipe: Recipe? = nil, onDelete: (() -> Void)? = nil) {
        self.existingRecipe = existingRecipe
        self.onDelete = onDelete
        _title = State(initialValue: existingRecipe?.title ?? "")
        _summary = State(initialValue: existingRecipe?.summary ?? "")
        _servingsText = State(initialValue: existingRecipe?.servings.map(String.init) ?? "")
        _difficulty = State(initialValue: existingRecipe?.difficulty ?? 1)
        _spiceLevel = State(initialValue: existingRecipe?.spiceLevel ?? 0)
        _soloCookTimeText = State(initialValue: existingRecipe.map { String($0.soloCookTimeMinutes) } ?? "")
        _dietaryTags = State(initialValue: Set(existingRecipe?.dietaryTags ?? []))
        _ingredients = State(initialValue: existingRecipe?.ingredients ?? [Ingredient(name: "", amount: "")])
        _steps = State(initialValue: existingRecipe?.soloSteps ?? [
            RecipeStep(order: 0, instruction: "", assignee: .solo, imageSystemName: "circle.fill")
        ])
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var soloCookTimeMinutes: Int? { Int(soloCookTimeText) }
    private var nonEmptyIngredients: [Ingredient] {
        ingredients.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var nonEmptySteps: [RecipeStep] {
        steps.filter { !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var isValid: Bool {
        !trimmedTitle.isEmpty
            && (soloCookTimeMinutes ?? 0) > 0
            && !nonEmptyIngredients.isEmpty
            && !nonEmptySteps.isEmpty
            // Servings is optional — but if something's been typed, it has to be a real positive
            // number, not "0" or garbage silently saved as nil/zero.
            && (servingsText.isEmpty || (Int(servingsText) ?? 0) > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("editorTitleField")
                    TextField("Summary", text: $summary, axis: .vertical)
                        .accessibilityIdentifier("editorSummaryField")
                    TextField("Servings (optional)", text: $servingsText)
                        .keyboardType(.numberPad)
                }

                Section("Details") {
                    Stepper("Difficulty: \(difficulty)", value: $difficulty, in: 1...3)
                    Stepper("Spice level: \(spiceLevel)", value: $spiceLevel, in: 0...3)
                    TextField("Cook time (minutes)", text: $soloCookTimeText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("editorCookTimeField")
                }

                Section("Dietary Tags") {
                    ForEach(DietaryTag.allCases, id: \.self) { tag in
                        Toggle(tag.label, isOn: Binding(
                            get: { dietaryTags.contains(tag) },
                            set: { isOn in
                                if isOn { dietaryTags.insert(tag) } else { dietaryTags.remove(tag) }
                            }
                        ))
                    }
                }

                Section("Ingredients") {
                    ForEach($ingredients) { $ingredient in
                        HStack {
                            TextField("Name", text: $ingredient.name)
                                .accessibilityIdentifier("ingredientNameField")
                            TextField("Amount", text: $ingredient.amount)
                                .frame(width: 100)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("ingredientAmountField")
                        }
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }
                    Button {
                        ingredients.append(Ingredient(name: "", amount: ""))
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("addIngredientButton")
                }

                Section("Steps") {
                    ForEach($steps) { $step in
                        TextField("Instruction", text: $step.instruction, axis: .vertical)
                            .accessibilityIdentifier("stepInstructionField")
                    }
                    .onDelete { indices in
                        steps.remove(atOffsets: indices)
                        renumberSteps()
                    }
                    .onMove { source, destination in
                        steps.move(fromOffsets: source, toOffset: destination)
                        renumberSteps()
                    }
                    Button {
                        steps.append(RecipeStep(order: steps.count, instruction: "", assignee: .solo, imageSystemName: "circle.fill"))
                    } label: {
                        Label("Add Step", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("addStepButton")
                }

                if existingRecipe?.isUserCreated == true {
                    Section {
                        Button("Delete Recipe", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(existingRecipe == nil ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                        .accessibilityIdentifier("saveRecipeButton")
                }
                ToolbarItem(placement: .topBarLeading) {
                    // Only meaningful for reordering steps/deleting ingredients — no separate
                    // "done editing" state to leave, so this just toggles drag handles/delete
                    // controls on and off.
                    EditButton()
                }
            }
            .confirmationDialog(
                "Delete this recipe?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    dismiss()
                    // The presenting screen (RecipeDetailView) is the one holding a live
                    // reference to this recipe — it navigates away first, then actually deletes,
                    // via this callback. See `onDelete`'s doc comment.
                    onDelete?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func renumberSteps() {
        for index in steps.indices {
            steps[index].order = index
        }
    }

    private func save() {
        // Belt-and-suspenders: `RecipeDetailView` only ever shows the Edit button for a
        // user-created recipe, but this view — not its caller — is the one that should actually
        // guarantee a bundled recipe's authored content can never be overwritten.
        if let existingRecipe, !existingRecipe.isUserCreated {
            assertionFailure("RecipeEditorView should never be editing a non-user-created recipe")
            dismiss()
            return
        }

        let servings = servingsText.isEmpty ? nil : Int(servingsText)
        let finalIngredients = nonEmptyIngredients
        let finalSteps = nonEmptySteps.enumerated().map { index, step -> RecipeStep in
            var step = step
            step.order = index
            return step
        }

        if let existingRecipe {
            existingRecipe.title = trimmedTitle
            existingRecipe.summary = summary
            existingRecipe.servings = servings
            existingRecipe.difficulty = difficulty
            existingRecipe.spiceLevel = spiceLevel
            existingRecipe.soloCookTimeMinutes = soloCookTimeMinutes ?? existingRecipe.soloCookTimeMinutes
            existingRecipe.dietaryTags = Array(dietaryTags)
            existingRecipe.ingredients = finalIngredients
            existingRecipe.soloSteps = finalSteps
        } else {
            let nextSortOrder = Recipe.nextSortOrder(after: allRecipes)
            let recipe = Recipe(
                title: trimmedTitle,
                summary: summary,
                servings: servings,
                soloSteps: finalSteps,
                iconSystemName: "fork.knife",
                difficulty: difficulty,
                spiceLevel: spiceLevel,
                soloCookTimeMinutes: soloCookTimeMinutes ?? 1,
                dietaryTags: Array(dietaryTags),
                ingredients: finalIngredients,
                sortOrder: nextSortOrder,
                isUserCreated: true
            )
            modelContext.insert(recipe)
        }
        try? modelContext.save()
        dismiss()
    }
}
