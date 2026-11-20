import SwiftUI
import JiggerCore
import JiggerEngine

/// Saved recipes with live costs (they follow My Ingredients prices), search, open, duplicate and delete with undo.
struct RecipesView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    let openCalculator: () -> Void

    var body: some View {
        let list = store.filteredRecipes(query)
        List {
            Section {
                Text("Costs follow your bottle prices. Change a price in My Ingredients and every recipe here recalculates.")
                    .font(Theme.subhead)
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if store.recipes.isEmpty {
                EmptyStateView(title: "No saved recipes yet",
                               message: "Cost a drink in the calculator and tap Save. It will show up here with its current cost.",
                               actionTitle: "Go to calculator", action: openCalculator)
                    .listRowBackground(Color.clear)
            } else if list.isEmpty {
                EmptyStateView(title: nil, message: "No recipe or ingredient matches “\(query)”.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(list) { recipe in
                    RecipeRow(recipe: recipe) {
                        store.openRecipe(recipe.id)
                        openCalculator()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { store.deleteRecipe(recipe.id) } label: { Label("Delete", systemImage: "trash") }
                        Button { store.duplicateRecipe(recipe.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            .tint(Theme.brass)
                    }
                    .contextMenu {
                        Button { store.openRecipe(recipe.id); openCalculator() } label: { Label("Open", systemImage: "pencil") }
                        Button { store.duplicateRecipe(recipe.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        Button(role: .destructive) { store.deleteRecipe(recipe.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Theme.line)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search recipes")
        .navigationTitle("Saved Recipes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PDFExportMenu(identifier: "recipesPDF", disabled: store.recipes.isEmpty) { store.recipeBook() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.startNewRecipe(); openCalculator() } label: { Text("New").font(Theme.body) }
                    .accessibilityLabel("New recipe")
                    .accessibilityIdentifier("newRecipeFromList")
            }
        }
    }
}

private struct RecipeRow: View {
    @Environment(AppStore.self) private var store
    let recipe: Recipe
    let open: () -> Void

    var body: some View {
        let t = store.totals(recipe)
        let n = recipe.lines.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(action: open) {
                    Text(recipe.name.isEmpty ? "Untitled drink" : recipe.name)
                        .font(Theme.heading(21, relativeTo: .title3))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open.\(recipe.name)")
                Spacer(minLength: 8)
                Menu {
                    Button { open() } label: { Label("Open", systemImage: "pencil") }
                    Button { store.duplicateRecipe(recipe.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { store.deleteRecipe(recipe.id) } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 40, height: 32)
                }
                .accessibilityLabel("Actions for \(recipe.name)")
                .accessibilityIdentifier("actions.\(recipe.name)")
            }
            Text("\(n) ingredient\(n == 1 ? "" : "s") · updated \(store.displayDate(recipe.updatedAt))")
                .font(Theme.caption)
                .foregroundStyle(Theme.faint)
            HStack(alignment: .top, spacing: 0) {
                figure("Cost", store.money(t.drinkCost), accent: false)
                figure("Menu", store.money(typed: recipe.menuPrice), accent: false)
                if t.bevCostPct != nil {
                    figure("Bev cost", formatPct(t.bevCostPct), accent: true)
                } else {
                    figure("Charge", store.money(t.suggestedPrice), accent: true)
                }
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe.\(recipe.name)")
    }

    private func figure(_ label: String, _ value: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).capsLabel()
            Text(value)
                .font(Theme.figure(20, relativeTo: .title3))
                .monospacedDigit()
                .foregroundStyle(accent ? Theme.brass : Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
