import SwiftUI
import JiggerCore

/// Sheet for adding a saved ingredient to the recipe.
struct LibraryPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            let items = store.filteredLibrary(query)
            List {
                if store.library.isEmpty {
                    Text("Nothing saved yet. Open any ingredient in Mix and tap Save to My Ingredients, or add one under My Ingredients.")
                        .font(Theme.callout)
                        .foregroundStyle(Theme.muted)
                } else if items.isEmpty {
                    Text("No saved ingredient matches “\(query)”.").font(Theme.callout).foregroundStyle(Theme.muted)
                } else {
                    ForEach(items) { item in
                        Button { onPick(item.id) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(item.name).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                                DotLeader()
                                Text(store.packageLabel(size: item.size, unit: item.sizeUnit))
                                    .font(Theme.caption).foregroundStyle(Theme.faint).fixedSize()
                                Text(store.money(typed: item.price))
                                    .font(Theme.futura(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.text).fixedSize()
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("pick.\(item.name)")
                    }
                }
            }
            .listStyle(.plain)
            .font(Theme.body)
            .searchable(text: $query, prompt: "Search saved ingredients")
            .keyboardDoneBar()
            .navigationTitle("My Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel").font(Theme.body) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
