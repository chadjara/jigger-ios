import SwiftUI
import JiggerCore
import JiggerEngine

/// My Ingredients: bottles bought often. A price changed here flows into every recipe using it,
/// except recipes with their own custom price for that line.
struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var editing: LibraryEditorTarget?

    var body: some View {
        let items = store.filteredLibrary(query)
        List {
            Section {
                Text("Save the bottles and produce you buy often. Change a price here and every recipe using it recalculates, unless that recipe has its own custom price.")
                    .font(Theme.subhead)
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                if store.library.isEmpty {
                    EmptyStateView(title: "Nothing saved yet",
                                   message: "Tap + to add a bottle, or open any ingredient in Mix and tap Save to My Ingredients.",
                                   actionTitle: "Add an ingredient") { editing = .new }
                        .listRowBackground(Color.clear)
                } else if items.isEmpty {
                    EmptyStateView(title: nil, message: "No ingredient matches “\(query)”.").listRowBackground(Color.clear)
                } else {
                    ForEach(items) { item in
                        LibraryRow(item: item) { editing = .item(item.id) }
                            .listRowBackground(Theme.surface)
                            .listRowSeparatorTint(Theme.line)
                            .swipeActions {
                                Button(role: .destructive) { store.deleteLibraryItem(item.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                if !store.library.isEmpty {
                    Text("Saved · \(store.library.count)").capsLabel()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search ingredients")
        .navigationTitle("My Ingredients")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PDFExportMenu(identifier: "ingredientsPDF", disabled: store.library.isEmpty) { store.ingredientPriceList() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = .new } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add ingredient")
                    .accessibilityIdentifier("libAdd")
            }
        }
        .sheet(item: $editing) { target in
            LibraryItemEditor(target: target)
        }
    }
}

/// A saved ingredient at a glance: name, package and price, cost per pour unit, and where it's used.
private struct LibraryRow: View {
    @Environment(AppStore.self) private var store
    let item: JiggerCore.LibraryItem // qualified: SwiftUI also exports a LibraryItem
    let open: () -> Void

    var body: some View {
        let used = store.usageCount(item.id)
        let bad = !store.invalidFields(item).isEmpty
        let unit = unitCost(price: item.price, size: item.size, sizeUnit: item.sizeUnit, volumeDisplayUnit: store.settings.displayUnit)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name.isEmpty ? "Unnamed ingredient" : item.name)
                    .font(Theme.body)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(store.packageLabel(size: item.size, unit: item.sizeUnit)) · \(store.money(typed: item.price))")
                    .font(Theme.caption)
                    .foregroundStyle(bad ? Theme.danger : Theme.muted)
                Text(used > 0 ? "In \(used) recipe\(used == 1 ? "" : "s")" : "Not in a recipe")
                    .font(Theme.caption)
                    .foregroundStyle(used > 0 ? Theme.brass : Theme.faint)
                    .accessibilityIdentifier("lib.\(item.name).used")
            }
            Spacer(minLength: 8)
            if let unit {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(store.money(unit.amount))
                        .font(Theme.figure(20, relativeTo: .title3))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Text("per \(unit.basis.label)").font(Theme.caption).foregroundStyle(Theme.faint)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.faint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Edit", open)
        .accessibilityIdentifier("lib.\(item.name)")
    }
}

enum LibraryEditorTarget: Identifiable, Hashable {
    case new
    case item(String)

    var id: String {
        switch self {
        case .new: return "new"
        case let .item(id): return id
        }
    }
}

/// Add or edit a saved ingredient in a native form. Edits to an existing item apply as you type;
/// a new item is added with Save once its details are valid.
struct LibraryItemEditor: View {
    enum Field: Hashable { case name, price, size }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let target: LibraryEditorTarget
    @State private var name = ""
    @State private var price = ""
    @State private var size = "750"
    @State private var unit: JiggerUnit = .ml
    @FocusState private var focus: Field?

    private var existingID: String? {
        if case let .item(id) = target { return id }
        return nil
    }

    var body: some View {
        let messages = store.libraryFieldMessages(name: name, price: price, size: size, sizeUnit: unit.rawValue, excluding: existingID)
        NavigationStack {
            Form {
                Section {
                    TextField("Ingredient name, e.g. Tito’s Vodka", text: $name)
                        .font(Theme.input)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focus = .price }
                        .focused($focus, equals: .name)
                        .accessibilityLabel("Ingredient name")
                        .accessibilityIdentifier("libEditor.name")
                } header: {
                    Text("Ingredient").capsLabel()
                } footer: {
                    FieldMessage(text: shown(messages[.name]), identifier: "libEditor.error.name")
                }
                .listRowBackground(Theme.surface)

                Section {
                    LabeledContent("Price paid") {
                        HStack(spacing: 4) {
                            Spacer(minLength: 0)
                            Text(store.currencySymbol).foregroundStyle(Theme.faint)
                            TextField("0.00", text: numeric($price))
                                .font(Theme.input)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                                .focused($focus, equals: .price)
                                .accessibilityLabel("Price paid")
                                .accessibilityIdentifier("libEditor.price")
                        }
                    }
                    LabeledContent("Package size") {
                        TextField("750", text: numeric($size))
                            .font(Theme.input)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .focused($focus, equals: .size)
                            .accessibilityLabel("Package size")
                            .accessibilityIdentifier("libEditor.size")
                    }
                    Picker("Unit", selection: $unit) {
                        ForEach(Catalog.packageUnits, id: \.self) { u in Text(u.label).tag(u) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("libEditor.unit")
                } header: {
                    Text("What you paid").capsLabel()
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldMessage(text: shown(messages[.price]), identifier: "libEditor.error.price")
                        FieldMessage(text: shown(messages[.size]), identifier: "libEditor.error.size")
                        if let id = existingID {
                            let used = store.usageCount(id)
                            Text(used > 0 ? "Used in \(used) saved recipe\(used == 1 ? "" : "s"). A new price updates them, except recipes with their own custom price."
                                          : "Not in a saved recipe yet.")
                                .font(Theme.footnote)
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                if let id = existingID {
                    Section {
                        Button(role: .destructive) {
                            dismiss()
                            store.deleteLibraryItem(id)
                        } label: { Label("Delete ingredient", systemImage: "trash") }
                            .accessibilityIdentifier("libEditor.delete")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existingID == nil ? "New ingredient" : (name.isEmpty ? "Ingredient" : name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if existingID == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.accessibilityIdentifier("libEditor.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { save() } label: { Text("Save").font(Theme.emphasis) }
                            .disabled(!messages.isEmpty)
                            .accessibilityIdentifier("libEditor.save")
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: { Text("Done").font(Theme.emphasis) }
                            .accessibilityIdentifier("libEditor.done")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { focus = nil } label: { Text("Done").font(Theme.emphasis) }
                        .accessibilityIdentifier("keyboardDone")
                }
            }
            .onAppear(perform: load)
            .onChange(of: name) { apply(.name, name) }
            .onChange(of: price) { apply(.price, price) }
            .onChange(of: size) { apply(.size, size) }
            .onChange(of: unit) { if let id = existingID { store.setLibrarySizeUnit(id, unit) } }
        }
        .tint(Theme.brass)
        .font(Theme.body)
    }

    /// New items stay quiet until something has been typed; existing items always show what's wrong.
    private func shown(_ message: String?) -> String? {
        guard existingID == nil else { return message }
        return name.isEmpty && price.isEmpty ? nil : message
    }

    private func load() {
        if let id = existingID, let item = store.libraryItem(id) {
            name = item.name
            price = item.price
            size = item.size
            unit = JiggerUnit(rawValue: item.sizeUnit) ?? .ml
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focus = .name }
        }
    }

    private func apply(_ field: LibraryTextField, _ value: String) {
        guard let id = existingID, let item = store.libraryItem(id) else { return }
        let current: String
        switch field {
        case .name: current = item.name
        case .price: current = item.price
        case .size: current = item.size
        }
        if current != value { store.updateLibraryItem(id, field, value) }
    }

    private func save() {
        if store.addLibraryItem(name: name, price: price, size: size, sizeUnit: unit) { dismiss() }
    }

    private func numeric(_ binding: Binding<String>) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = store.normalizeTyped(String($0.prefix(20))) })
    }
}
