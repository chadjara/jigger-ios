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
                    Text("Nothing saved yet. Use the bookmark on any ingredient row to save it here, or add bottles under My Ingredients.")
                        .foregroundStyle(Theme.muted)
                } else if items.isEmpty {
                    Text("No saved ingredient matches “\(query)”.").foregroundStyle(Theme.muted)
                } else {
                    ForEach(items) { item in
                        Button { onPick(item.id) } label: {
                            HStack {
                                Text(item.name).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(store.packageLabel(size: item.size, unit: item.sizeUnit)), \(store.money(typed: item.price))")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .accessibilityIdentifier("pick.\(item.name)")
                    }
                }
            }
            .searchable(text: $query, prompt: "Search saved ingredients")
            .navigationTitle("My Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
