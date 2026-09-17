import SwiftUI
import SwiftData
import CookingAppCore

/// The in-app shopping list — items added from a recipe's "Add to Shopping List" button
/// (`RecipeDetailView`), checked off while actually shopping. Presented as a sheet from
/// `RecipeListView`'s toolbar rather than a `Route` case, the same pattern `RecipeEditorView` and
/// `WelcomeNameView` already use for a screen that isn't part of the core recipe-browsing/cooking
/// navigation stack.
struct ShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ShoppingListItem.dateAdded) private var items: [ShoppingListItem]

    /// Unchecked first (oldest-added first within each group), so what you still need to buy
    /// stays at the top rather than getting buried under everything you've already checked off.
    private var uncheckedItems: [ShoppingListItem] { items.filter { !$0.isChecked } }
    private var checkedItems: [ShoppingListItem] { items.filter(\.isChecked) }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Shopping List Is Empty",
                        systemImage: "cart",
                        description: Text("Add ingredients from a recipe's \"Add to Shopping List\" button.")
                    )
                }

                if !uncheckedItems.isEmpty {
                    Section("To Buy") {
                        ForEach(uncheckedItems) { item in
                            row(for: item)
                        }
                        .onDelete { deleteItems(uncheckedItems, at: $0) }
                    }
                }

                if !checkedItems.isEmpty {
                    Section("Checked Off") {
                        ForEach(checkedItems) { item in
                            row(for: item)
                        }
                        .onDelete { deleteItems(checkedItems, at: $0) }
                    }
                }
            }
            .navigationTitle("Shopping List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                if !checkedItems.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear Checked") {
                            for item in checkedItems { modelContext.delete(item) }
                            try? modelContext.save()
                        }
                        .accessibilityIdentifier("clearCheckedItemsButton")
                    }
                }
            }
        }
    }

    private func row(for item: ShoppingListItem) -> some View {
        Button {
            item.isChecked.toggle()
            try? modelContext.save()
        } label: {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                    if let sourceRecipeTitle = item.sourceRecipeTitle {
                        Text("from \(sourceRecipeTitle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(item.amount)
                    .foregroundStyle(.secondary)
            }
            // Combines name/source/amount into one VoiceOver stop instead of three fragments;
            // the checkmark icon is hidden above since `.isSelected` below already conveys
            // checked state (VoiceOver appends "selected" itself).
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shoppingListItem_\(item.name)")
        .accessibilityAddTraits(item.isChecked ? [.isSelected] : [])
    }

    private func deleteItems(_ group: [ShoppingListItem], at offsets: IndexSet) {
        for index in offsets { modelContext.delete(group[index]) }
        try? modelContext.save()
    }
}
