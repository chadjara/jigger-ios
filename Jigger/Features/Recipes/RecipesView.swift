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
                Text("Costs update automatically when you change prices in My Ingredients.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
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
                    .listRowBackground(Theme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search recipes")
        .navigationTitle("Saved Recipes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Recipe") { store.startNewRecipe(); openCalculator() }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Button(action: open) {
                    Text(recipe.name.isEmpty ? "Untitled drink" : recipe.name)
                        .font(Theme.heading(20, relativeTo: .headline))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open.\(recipe.name)")
                Spacer()
                Menu {
                    Button { open() } label: { Label("Open", systemImage: "pencil") }
                    Button { store.duplicateRecipe(recipe.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { store.deleteRecipe(recipe.id) } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Theme.muted).frame(width: 36, height: 36)
                }
                .accessibilityLabel("Actions for \(recipe.name)")
                .accessibilityIdentifier("actions.\(recipe.name)")
            }
            Text("\(n) ingredient\(n == 1 ? "" : "s"), updated \(store.displayDate(recipe.updatedAt))")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            HStack(alignment: .top) {
                figure("Cost per drink", store.money(t.drinkCost))
                figure("Menu price", store.money(typed: recipe.menuPrice))
                if t.bevCostPct != nil {
                    figure("Beverage cost", formatPct(t.bevCostPct))
                } else {
                    figure("Suggested price", store.money(t.suggestedPrice))
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe.\(recipe.name)")
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Theme.muted)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
