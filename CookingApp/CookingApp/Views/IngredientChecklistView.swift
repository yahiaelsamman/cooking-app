import SwiftUI
import CookingAppCore

/// A "did I actually grab everything" checklist, reachable from `StepView` without leaving cook
/// mode — previously the only place to see a recipe's ingredients at all was the pre-cook overview
/// screen (`RecipeDetailView`), so double-checking mid-recipe meant backing out of the step flow
/// entirely. Deliberately whole-recipe, not per-step: `RecipeStep` has no per-step ingredient
/// association today (see its doc comment on `checkHint` for the same reasoning applied to
/// doneness data — adding one would mean hand-authoring it across every step of all 20 bundled
/// recipes), and "do I have everything for this dish" is the real question this answers regardless.
struct IngredientChecklistView: View {
    let ingredients: [Ingredient]
    /// The servings scale chosen on the recipe screen, so amounts match what you planned with.
    var scaleFactor: Double = 1
    @Binding var checkedNames: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ingredients) { ingredient in
                let isChecked = checkedNames.contains(ingredient.name)
                Button {
                    if isChecked {
                        checkedNames.remove(ingredient.name)
                    } else {
                        checkedNames.insert(ingredient.name)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isChecked ? Color.accentColor : .secondary)
                            .font(.title3)
                            .accessibilityHidden(true)
                            .contentTransition(.symbolEffect(.replace))
                        Text(ingredient.name)
                            .strikethrough(isChecked)
                            .foregroundStyle(isChecked ? .secondary : .primary)
                        Spacer()
                        Text(ingredient.scaledAmount(by: scaleFactor))
                            .foregroundStyle(.secondary)
                    }
                    // Combines name/amount into one VoiceOver stop instead of three fragments —
                    // matches ShoppingListView's structurally identical row exactly, including
                    // why: the checkmark icon is hidden above since `.isSelected` below already
                    // conveys checked state (VoiceOver appends "selected" itself).
                    .accessibilityElement(children: .combine)
                    .animation(.default, value: isChecked)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isChecked)
                .accessibilityIdentifier("ingredientChecklistRow_\(ingredient.name)")
                .accessibilityAddTraits(isChecked ? [.isSelected] : [])
            }
            .navigationTitle("Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
