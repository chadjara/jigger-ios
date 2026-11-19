import SwiftUI
import JiggerCore
import JiggerEngine

/// My Ingredients: bottles bought often. A price changed here flows into every recipe using it,
/// except recipes with their own custom price for that line.
struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var newName = ""
    @State private var newPrice = ""
    @State private var newSize = "750"
    @State private var newUnit: JiggerUnit = .ml
    @FocusState private var newNameFocused: Bool
    /// Row order is fixed while editing, so a row doesn't jump as its name is retyped; it re-sorts on search or add/delete.
    @State private var order: [String] = []

    var body: some View {
        let items = order.compactMap { store.libraryItem($0) }
        List {
            Section {
                Text("Save bottles you buy often. Change a price here and every recipe using it recalculates, unless that recipe has its own custom price.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            }
            Section("Add an ingredient") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Ingredient, e.g. Tito’s Vodka", text: $newName)
                        .textInputAutocapitalization(.words)
                        .focused($newNameFocused)
                        .accessibilityIdentifier("libNew.name")
                    HStack(spacing: 8) {
                        JField(label: "Price paid", text: normalized($newPrice), placeholder: "0.00", prefix: store.currencySymbol,
                               identifier: "libNew.price")
                        JField(label: "Package size", text: normalized($newSize), placeholder: "750", identifier: "libNew.size")
                        UnitMenu(current: newUnit) { newUnit = $0 }
                    }
                    Button("Add ingredient") { add() }
                        .buttonStyle(.jPrimary)
                        .accessibilityIdentifier("libAdd")
                }
                .padding(.vertical, 4)
                .listRowBackground(Theme.surface)
            }
            Section {
                if store.library.isEmpty {
                    EmptyStateView(title: "No saved ingredients yet",
                                   message: "Add a bottle above, or tap the bookmark on any ingredient row in the calculator.")
                        .listRowBackground(Color.clear)
                } else if items.isEmpty {
                    EmptyStateView(title: nil, message: "No ingredient matches “\(query)”.").listRowBackground(Color.clear)
                } else {
                    ForEach(items) { item in
                        LibraryRow(item: item)
                            .listRowBackground(Theme.surface)
                            .swipeActions {
                                Button(role: .destructive) { store.deleteLibraryItem(item.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $query, prompt: "Search ingredients")
        .navigationTitle("My Ingredients")
        .onAppear(perform: resort)
        .onChange(of: query) { resort() }
        .onChange(of: store.library.count) { resort() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
    }

    private func resort() {
        order = store.filteredLibrary(query).map(\.id)
    }

    private func add() {
        guard store.addLibraryItem(name: newName, price: newPrice, size: newSize, sizeUnit: newUnit) else { return }
        newName = ""
        newPrice = ""
        newNameFocused = true
    }

    private func normalized(_ binding: Binding<String>) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = store.normalizeTyped($0) })
    }
}

/// Menu for choosing a package unit, styled like a field.
struct UnitMenu: View {
    let current: JiggerUnit?
    let choose: (JiggerUnit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(" ").font(Theme.label)
            Menu {
                ForEach(Catalog.packageUnits, id: \.self) { u in Button(u.label) { choose(u) } }
            } label: {
                HStack(spacing: 4) {
                    Text(current?.label ?? "Unit")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 40)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.line))
            }
            .fixedSize()
            .accessibilityLabel("Package unit")
        }
    }
}

private struct LibraryRow: View {
    @Environment(AppStore.self) private var store
    let item: JiggerCore.LibraryItem // qualified: SwiftUI also exports a LibraryItem

    var body: some View {
        let bad = store.invalidFields(item)
        let used = store.usageCount(item.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                JField(label: "Ingredient", text: field(.name, item.name), keyboard: .default, invalid: bad.contains(.name),
                       identifier: "lib.\(item.name).name")
                IconButton(systemImage: "trash", label: "Delete \(item.name)", danger: true, identifier: "lib.\(item.name).delete") {
                    store.deleteLibraryItem(item.id)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                JField(label: "Price paid", text: field(.price, item.price), placeholder: "0.00", prefix: store.currencySymbol,
                       invalid: bad.contains(.price), identifier: "lib.\(item.name).price")
                JField(label: "Package size", text: field(.size, item.size), invalid: bad.contains(.size),
                       identifier: "lib.\(item.name).size")
                UnitMenu(current: JiggerUnit(rawValue: item.sizeUnit)) { store.setLibrarySizeUnit(item.id, $0) }
            }
            Text(used > 0 ? "In \(used) recipe\(used == 1 ? "" : "s")" : "Not in a recipe")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .accessibilityIdentifier("lib.\(item.name).used")
        }
        .padding(.vertical, 4)
    }

    private func field(_ f: LibraryTextField, _ current: String) -> Binding<String> {
        Binding(get: { current }, set: { store.updateLibraryItem(item.id, f, f == .name ? String($0.prefix(80)) : store.normalizeTyped($0)) })
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
