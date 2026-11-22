import SwiftUI
import JiggerCore
import JiggerEngine

/// Which ingredient the editor sheet is open for, and which field to focus first.
struct EditorTarget: Identifiable, Equatable {
    let id: String
    var focus: IngredientEditor.Field?
}

/// One ingredient, edited in a native grouped form: what you paid, the package, the pour and waste.
/// Changes apply as you type; the cost at the top updates live.
struct IngredientEditor: View {
    enum Field: Hashable { case name, price, size, amount, waste }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let lineID: String
    var focusOnOpen: Field?
    /// Also show Done along the bottom (regular-width screens; see `sheetActionBar`).
    var actionBar = false
    @FocusState private var focus: Field?

    var body: some View {
        NavigationStack {
            Group {
                if let line = store.draft.lines.first(where: { $0.id == lineID }) {
                    form(line)
                } else {
                    // The line was removed (or the recipe changed underneath); nothing to edit.
                    Color.clear.onAppear { dismiss() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focus == .amount, let line = store.draft.lines.first(where: { $0.id == lineID }) {
                        ForEach(["½", "¼", "¾"], id: \.self) { f in
                            Button(f) { addFraction(f, line) }
                                .font(.body.weight(.semibold))
                                .accessibilityLabel(spoken(f))
                                .accessibilityIdentifier("fraction.\(f)")
                        }
                        Button("/") { store.setLine(line.id, .amount, store.displayAmount(line) + "/") }
                            .font(.body.weight(.semibold))
                            .accessibilityLabel("Fraction bar")
                    }
                    Spacer()
                    Button { focus = nil } label: { Text("Done").font(Theme.emphasis) }
                        .accessibilityIdentifier("keyboardDone")
                }
            }
        }
        .tint(Theme.brass)
        .font(Theme.body)
        .onAppear {
            guard let f = focusOnOpen else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focus = f }
        }
    }

    // MARK: - Form

    private func form(_ line: Line) -> some View {
        let resolved = store.resolve(line)
        let item = store.libraryItem(line.libId)
        let totals = store.draftTotals
        let result = totals.line(line.id)
        let errors = result?.errors ?? [:]
        let warnings = result?.warnings ?? [:]
        let dim = dimension(of: resolved.sizeUnit) ?? .volume
        let number = (store.draft.lines.firstIndex { $0.id == line.id } ?? 0) + 1

        return Form {
            // Live cost
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cost per drink").capsLabel()
                        Text(store.lineShareText(result, totals: totals))
                            .font(Theme.caption).foregroundStyle(Theme.faint)
                    }
                    Spacer()
                    Text(store.lineCostText(result))
                        .font(Theme.figure(34, relativeTo: .title))
                        .monospacedDigit()
                        .foregroundStyle(result?.status == .ok ? Theme.text : Theme.faint)
                        .accessibilityIdentifier("editor.cost")
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Theme.surface)

            // Name
            Section {
                TextField("Ingredient name, e.g. Tito’s Vodka", text: nameBinding(line, resolved))
                    .font(Theme.input)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit { focus = item == nil ? .price : .amount }
                    .disabled(item != nil)
                    .foregroundStyle(item != nil ? Theme.muted : Theme.text)
                    .focused($focus, equals: .name)
                    .accessibilityLabel("Ingredient name")
                    .accessibilityIdentifier("editor.name")
                if item == nil {
                    Button { saveToLibrary(line) } label: {
                        Label("Save to My Ingredients", systemImage: "bookmark")
                    }
                    .accessibilityIdentifier("editor.saveToLibrary")
                }
            } header: {
                Text("Ingredient").capsLabel()
            } footer: {
                if item != nil {
                    Text(line.priceOverride ? "From My Ingredients, with a custom price in this recipe."
                                            : "From My Ingredients. Edit its name and package there; the price flows into every recipe.")
                        .font(Theme.footnote)
                        .accessibilityIdentifier("editor.tag")
                }
            }
            .listRowBackground(Theme.surface)

            // Price and package
            Section {
                LabeledContent("Price paid") {
                    HStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Text(store.currencySymbol).foregroundStyle(Theme.faint)
                        TextField("0.00", text: textBinding(line, .price, resolved.price))
                            .font(Theme.input)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .focused($focus, equals: .price)
                            .accessibilityLabel("Price paid")
                            .accessibilityIdentifier("editor.price")
                    }
                }
                if let item, line.priceOverride {
                    Button("Use saved price, \(store.money(typed: item.price))") { store.revertPrice(line.id) }
                        .accessibilityIdentifier("editor.revertPrice")
                }
                packageRows(line, resolved: resolved, linked: item != nil)
            } header: {
                Text("What you paid").capsLabel()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    FieldMessage(text: errors[.price], identifier: "editor.error.price")
                    FieldMessage(text: errors[.size], identifier: "editor.error.size")
                }
            }
            .listRowBackground(Theme.surface)

            // Pour
            Section {
                HStack(spacing: 10) {
                    TextField(dim == .count ? "1/2" : "0", text: amountBinding(line))
                        .font(Theme.input)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 110)
                        .focused($focus, equals: .amount)
                        .accessibilityLabel("Used per drink")
                        .accessibilityIdentifier("editor.amount")
                    amountUnit(line, dim: dim)
                    Spacer(minLength: 0)
                    Stepper("Adjust pour", onIncrement: { store.stepPour(line.id, by: 1) },
                            onDecrement: { store.stepPour(line.id, by: -1) })
                        .labelsHidden()
                        .accessibilityLabel("Adjust pour by \(plainString(store.pourStep(line))) \(store.unitLabel(store.displayAmountUnit(line), pour: true))")
                        .accessibilityIdentifier("editor.stepper")
                }
                if dim == .volume {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Catalog.pours(for: store.settings.displayUnit), id: \.self) { pour in
                                Chip(title: pour, selected: store.isPourSelected(line, pour), identifier: "editor.pour.\(pour)") {
                                    store.tapPour(line.id, pour)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityLabel("Common pours")
                }
                if let note = store.enteredAsNote(line) {
                    Text(note).font(Theme.note).foregroundStyle(Theme.muted).accessibilityIdentifier("editor.enteredAs")
                }
            } header: {
                Text("Used per drink").capsLabel()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    FieldMessage(text: errors[.amount], identifier: "editor.error.amount")
                    FieldMessage(text: warnings[.amount], kind: .warning, identifier: "editor.warning.amount")
                }
            }
            .listRowBackground(Theme.surface)

            // Waste
            Section {
                LabeledContent("Waste") {
                    HStack(spacing: 4) {
                        Spacer(minLength: 0)
                        TextField(store.draft.wastePct.isEmpty ? "0" : store.draft.wastePct, text: textBinding(line, .wastePct, line.wastePct))
                            .font(Theme.input)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 70)
                            .focused($focus, equals: .waste)
                            .accessibilityLabel("Waste percent for this ingredient")
                            .accessibilityIdentifier("editor.waste")
                        Text("%").foregroundStyle(Theme.faint)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    FieldMessage(text: errors[.waste], identifier: "editor.error.waste")
                    FieldMessage(text: warnings[.waste], kind: .warning, identifier: "editor.warning.waste")
                    Text(store.draft.wastePct.isEmpty
                         ? "Spills and spoilage. Leave empty for no waste, or set one % for every ingredient on the Mix screen."
                         : "Leave empty to use the recipe’s \(store.draft.wastePct)% waste.")
                        .font(Theme.footnote)
                }
            }
            .listRowBackground(Theme.surface)

            Section {
                Button(role: .destructive) {
                    dismiss()
                    store.removeLine(line.id)
                } label: {
                    Label("Remove ingredient", systemImage: "trash")
                }
                .accessibilityIdentifier("editor.remove")
            }
            .listRowBackground(Theme.surface)
        }
        .keyboardDoneBarless()
        .navigationTitle(resolved.name.isEmpty ? "Ingredient \(number)" : resolved.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: { Text("Done").font(Theme.emphasis) }
                    .accessibilityIdentifier("editor.done")
            }
        }
        .sheetActionBar(actionBar, [SheetAction(id: "editor.doneBar", title: "Done") { dismiss() }])
    }

    // MARK: - Package and unit

    @ViewBuilder
    private func packageRows(_ line: Line, resolved: Line, linked: Bool) -> some View {
        if linked {
            LabeledContent("Package", value: store.packageLabel(size: resolved.size, unit: resolved.sizeUnit))
                .accessibilityIdentifier("editor.package")
        } else if line.pkgMode != "custom" {
            Picker("Package", selection: presetBinding(line)) {
                ForEach(Catalog.packagePresets) { p in Text(p.label).tag(p.id) }
                if !Catalog.isPreset(size: line.size, unit: line.sizeUnit) {
                    Text(store.packageLabel(size: line.size, unit: line.sizeUnit)).tag("current")
                }
                Text("Custom size or unit…").tag("custom")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("editor.package")
        } else {
            LabeledContent("Package size") {
                TextField("Size", text: textBinding(line, .size, line.size))
                    .font(Theme.input)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                    .focused($focus, equals: .size)
                    .accessibilityLabel("Package size")
                    .accessibilityIdentifier("editor.size")
            }
            Picker("Unit", selection: Binding(get: { JiggerUnit(rawValue: line.sizeUnit) ?? .ml },
                                              set: { store.setSizeUnit(line.id, $0) })) {
                ForEach(Catalog.packageUnits, id: \.self) { u in Text(u.label).tag(u) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("editor.sizeUnit")
            Button("Use bottle sizes") { store.usePresetPackages(line.id) }
        }
    }

    @ViewBuilder
    private func amountUnit(_ line: Line, dim: UnitDimension) -> some View {
        switch dim {
        case .volume:
            Text(store.unitLabel(store.settings.displayUnit, pour: true)).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("editor.unit")
        case .count:
            Text("each").foregroundStyle(Theme.muted).accessibilityIdentifier("editor.unit")
        case .weight:
            Picker("Pour unit", selection: Binding(get: { JiggerUnit(rawValue: line.amountUnit) ?? .g },
                                                   set: { store.setAmountUnit(line.id, $0) })) {
                ForEach(Catalog.weightPourUnits, id: \.self) { u in Text(u.label).tag(u) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("editor.amountUnit")
        }
    }

    // MARK: - Actions and bindings

    private func saveToLibrary(_ line: Line) {
        switch store.saveLineToLibrary(line.id) {
        case .needsName: focus = .name
        case .needsPrice: focus = .price
        case .needsSize: focus = .size
        case .saved: focus = nil
        }
    }

    /// "½" after a whole number makes a mixed number ("1" → "1 1/2"); otherwise it replaces the pour.
    private func addFraction(_ symbol: String, _ line: Line) {
        let f = ["½": "1/2", "¼": "1/4", "¾": "3/4"][symbol] ?? symbol
        let current = store.displayAmount(line).trimmingCharacters(in: .whitespaces)
        let next = Int(current).map { $0 > 0 ? "\($0) \(f)" : f } ?? f
        store.setLine(line.id, .amount, next)
    }

    private func spoken(_ symbol: String) -> String {
        ["½": "One half", "¼": "One quarter", "¾": "Three quarters"][symbol] ?? symbol
    }

    private func nameBinding(_ line: Line, _ resolved: Line) -> Binding<String> {
        Binding(get: { resolved.name }, set: { store.setLine(line.id, .name, String($0.prefix(80))) })
    }

    private func textBinding(_ line: Line, _ field: LineTextField, _ current: String) -> Binding<String> {
        Binding(get: { current }, set: { store.setLine(line.id, field, store.normalizeTyped(String($0.prefix(20)))) })
    }

    /// The pour as shown in the current oz/mL setting; typing replaces it in that unit.
    private func amountBinding(_ line: Line) -> Binding<String> {
        Binding(get: { store.displayAmount(line) },
                set: { store.setLine(line.id, .amount, store.normalizePour(String($0.prefix(20)))) })
    }

    private func presetBinding(_ line: Line) -> Binding<String> {
        Binding(get: {
            Catalog.isPreset(size: line.size, unit: line.sizeUnit) ? "\(line.size)|\(line.sizeUnit)" : "current"
        }, set: { value in
            if value == "custom" {
                store.useCustomPackage(line.id)
                DispatchQueue.main.async { focus = .size }
            } else if let p = Catalog.packagePresets.first(where: { $0.id == value }) {
                store.choosePreset(line.id, p)
            }
        })
    }
}

private extension View {
    /// The editor declares its own keyboard bar (with fraction keys), so it only adds drag-to-dismiss.
    func keyboardDoneBarless() -> some View { scrollDismissesKeyboard(.interactively) }
}
