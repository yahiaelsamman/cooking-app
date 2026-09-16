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
    @Binding var checkedIDs: Set<Ingredient.ID>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ingredients) { ingredient in
                let isChecked = checkedIDs.contains(ingredient.id)
                Button {
                    if isChecked {
                        checkedIDs.remove(ingredient.id)
                    } else {
                        checkedIDs.insert(ingredient.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isChecked ? Color.accentColor : .secondary)
                            .font(.title3)
                        Text(ingredient.name)
                            .strikethrough(isChecked)
                            .foregroundStyle(isChecked ? .secondary : .primary)
                        Spacer()
                        Text(ingredient.amount)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
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
