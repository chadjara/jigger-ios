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
                Text("Save the bottles and produce you buy often. Change a price here and every recipe using it recalculates, unless that recipe has its own custom price.")
                    .font(Theme.subhead)
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    RuleHeader(title: "Add an ingredient")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ingredient").capsLabel()
                        TextField("e.g. Tito’s Vodka", text: $newName)
                            .font(Theme.body)
                            .textInputAutocapitalization(.words)
                            .focused($newNameFocused)
                            .frame(minHeight: 36)
                            .accessibilityLabel("Ingredient")
                            .accessibilityIdentifier("libNew.name")
                        Hairline(color: Theme.lineStrong)
                    }
                    HStack(alignment: .bottom, spacing: 16) {
                        JField(label: "Price paid", text: normalized($newPrice), placeholder: "0.00", prefix: store.currencySymbol,
                               identifier: "libNew.price")
                        JField(label: "Package size", text: normalized($newSize), placeholder: "750", identifier: "libNew.size")
                        UnitMenu(current: newUnit) { newUnit = $0 }
                    }
                    Button { add() } label: { Label("Add ingredient", systemImage: "plus") }
                        .buttonStyle(.jPrimary)
                        .accessibilityIdentifier("libAdd")
                }
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            Section {
                RuleHeader(title: "Saved", trailing: store.library.isEmpty ? nil : String(format: "%02d", store.library.count))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if store.library.isEmpty {
                    EmptyStateView(title: "Nothing saved yet",
                                   message: "Add one above, or tap the bookmark on any ingredient in Mix.")
                        .listRowBackground(Color.clear)
                } else if items.isEmpty {
                    EmptyStateView(title: nil, message: "No ingredient matches “\(query)”.").listRowBackground(Color.clear)
                } else {
                    ForEach(items) { item in
                        LibraryRow(item: item)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.line)
                            .swipeActions {
                                Button(role: .destructive) { store.deleteLibraryItem(item.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $query, prompt: "Search ingredients")
        .navigationTitle("My Ingredients")
        .onAppear(perform: resort)
        .onChange(of: query) { resort() }
        .onChange(of: store.library.count) { resort() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PDFExportMenu(identifier: "ingredientsPDF", disabled: store.library.isEmpty) { store.ingredientPriceList() }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { hideKeyboard() } label: { Text("Done").font(Theme.emphasis) }
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
            Text("Unit").capsLabel()
            Menu {
                ForEach(Catalog.packageUnits, id: \.self) { u in Button(u.label) { choose(u) } }
            } label: {
                MenuFieldLabel(text: current?.label ?? "Unit")
            }
            .accessibilityLabel("Package unit")
        }
        .frame(width: 84)
    }
}

private struct LibraryRow: View {
    @Environment(AppStore.self) private var store
    let item: JiggerCore.LibraryItem // qualified: SwiftUI also exports a LibraryItem

    var body: some View {
        let bad = store.invalidFields(item)
        let used = store.usageCount(item.id)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 0) {
                JField(label: "Ingredient", text: field(.name, item.name), keyboard: .default, invalid: bad.contains(.name),
                       identifier: "lib.\(item.name).name")
                IconButton(systemImage: "trash", label: "Delete \(item.name)", danger: true, identifier: "lib.\(item.name).delete") {
                    store.deleteLibraryItem(item.id)
                }
            }
            HStack(alignment: .bottom, spacing: 16) {
                JField(label: "Price paid", text: field(.price, item.price), placeholder: "0.00", prefix: store.currencySymbol,
                       invalid: bad.contains(.price), identifier: "lib.\(item.name).price")
                JField(label: "Package size", text: field(.size, item.size), invalid: bad.contains(.size),
                       identifier: "lib.\(item.name).size")
                UnitMenu(current: JiggerUnit(rawValue: item.sizeUnit)) { store.setLibrarySizeUnit(item.id, $0) }
            }
            Text(used > 0 ? "In \(used) recipe\(used == 1 ? "" : "s")" : "Not in a recipe")
                .font(Theme.caption)
                .foregroundStyle(used > 0 ? Theme.brass : Theme.faint)
                .accessibilityIdentifier("lib.\(item.name).used")
        }
        .padding(.vertical, 14)
    }

    private func field(_ f: LibraryTextField, _ current: String) -> Binding<String> {
        Binding(get: { current }, set: { store.updateLibraryItem(item.id, f, f == .name ? String($0.prefix(80)) : store.normalizeTyped($0)) })
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
