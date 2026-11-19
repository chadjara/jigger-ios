import SwiftUI
import JiggerCore
import JiggerEngine

/// One ingredient: what you paid, the package, how much goes in the drink, and what that costs.
struct IngredientRow: View {
    @Environment(AppStore.self) private var store
    let line: Line
    let index: Int
    let totals: RecipeTotals
    var focus: FocusState<FieldFocus?>.Binding

    var body: some View {
        let resolved = store.resolve(line)
        let item = store.libraryItem(line.libId)
        let result = totals.line(line.id)
        let errors = result?.errors ?? [:]
        let dim = dimension(of: resolved.sizeUnit) ?? .volume
        let displayName = resolved.name.isEmpty ? "ingredient" : resolved.name

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 4) {
                JField(label: "Ingredient", text: binding(.name, resolved.name), placeholder: "e.g. Tito’s Vodka",
                       keyboard: .default, disabled: item != nil, identifier: id("name"),
                       focus: focus, focusValue: .line(line.id, .name))
                if item == nil {
                    IconButton(systemImage: "bookmark", label: "Save \(displayName) to My Ingredients", identifier: id("saveToLibrary")) {
                        switch store.saveLineToLibrary(line.id) {
                        case .needsName: focus.wrappedValue = .line(line.id, .name)
                        case .needsPrice: focus.wrappedValue = .line(line.id, .price)
                        case .needsSize: focus.wrappedValue = .line(line.id, .size)
                        case .saved: break
                        }
                    }
                }
                IconButton(systemImage: "xmark", label: "Remove \(displayName)", danger: true, identifier: id("remove")) {
                    focus.wrappedValue = nil
                    store.removeLine(line.id)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                JField(label: "Price paid", text: binding(.price, resolved.price), placeholder: "0.00",
                       prefix: store.currencySymbol, invalid: errors[.price] != nil, identifier: id("price"),
                       focus: focus, focusValue: .line(line.id, .price))
                    .frame(maxWidth: 140)
                packageField(resolved: resolved, linked: item != nil, invalid: errors[.size] != nil)
            }

            HStack(alignment: .bottom, spacing: 8) {
                HStack(alignment: .bottom, spacing: 6) {
                    JField(label: "Used per drink", text: amountBinding, placeholder: dim == .count ? "e.g. 1/2" : "0",
                           keyboard: .numbersAndPunctuation, invalid: errors[.amount] != nil, identifier: id("amount"),
                           focus: focus, focusValue: .line(line.id, .amount))
                        .frame(maxWidth: 140)
                    amountUnit(dim: dim)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(store.lineCostText(result))
                        .font(.headline)
                        .monospacedDigit()
                        .accessibilityIdentifier(id("cost"))
                    Text(store.lineShareText(result, totals: totals))
                        .font(.caption)
                        .foregroundStyle(Theme.faint)
                }
                .padding(.bottom, 8)
            }

            if dim == .volume {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Catalog.pours(for: store.settings.displayUnit), id: \.self) { pour in
                            Chip(title: pour, selected: store.isPourSelected(line, pour), identifier: id("pour.\(pour)")) {
                                store.tapPour(line.id, pour)
                            }
                        }
                    }
                }
                .accessibilityLabel("Common pours in \(store.unitLabel(store.settings.displayUnit, pour: true))")
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    if let item {
                        if line.priceOverride {
                            Label("Custom price in this recipe", systemImage: "bookmark.fill")
                                .accessibilityIdentifier(id("tag"))
                            Button("Use saved \(store.money(typed: item.price))") { store.revertPrice(line.id) }
                                .font(.caption.weight(.medium))
                                .accessibilityIdentifier(id("revertPrice"))
                        } else {
                            Label("From My Ingredients", systemImage: "bookmark.fill")
                                .accessibilityIdentifier(id("tag"))
                        }
                    }
                    if let note = store.enteredAsNote(line) {
                        Text(note).foregroundStyle(Theme.muted).accessibilityIdentifier(id("enteredAs"))
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.brass)
                Spacer(minLength: 0)
                JField(label: nil, text: binding(.wastePct, line.wastePct),
                       placeholder: store.draft.wastePct.isEmpty ? "0" : store.draft.wastePct, prefix: "Waste", suffix: "%",
                       invalid: errors[.waste] != nil, identifier: id("waste"),
                       focus: focus, focusValue: .line(line.id, .wastePct), spokenLabel: "Waste percent for this ingredient")
                    .frame(width: 130)
                    .font(.footnote)
            }

            if let result, !result.errorMessages.isEmpty {
                Text(result.errorMessages.joined(separator: ". "))
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier(id("error"))
            }
        }
        .card(invalid: !errors.isEmpty)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("row\(index)")
    }

    // MARK: - Pieces

    @ViewBuilder
    private func packageField(resolved: Line, linked: Bool, invalid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Package").font(Theme.label).foregroundStyle(Theme.muted)
            if linked {
                Text(store.packageLabel(size: resolved.size, unit: resolved.sizeUnit))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .accessibilityHint("Edit the package in My Ingredients")
                    .accessibilityIdentifier(id("package"))
            } else if line.pkgMode != "custom" {
                Menu {
                    ForEach(Catalog.packagePresets) { p in
                        Button(p.label) { store.choosePreset(line.id, p) }
                    }
                    Divider()
                    Button("Custom size or unit…") {
                        store.useCustomPackage(line.id)
                        DispatchQueue.main.async { focus.wrappedValue = .line(line.id, .size) }
                    }
                } label: {
                    menuLabel(Catalog.isPreset(size: line.size, unit: line.sizeUnit)
                              ? "\(store.packageLabel(size: line.size, unit: line.sizeUnit)) bottle"
                              : store.packageLabel(size: line.size, unit: line.sizeUnit), invalid: invalid)
                }
                .accessibilityLabel("Package size")
                .accessibilityIdentifier(id("package"))
            } else {
                HStack(spacing: 6) {
                    JField(label: nil, text: binding(.size, line.size), placeholder: "Size", invalid: invalid,
                           identifier: id("size"), focus: focus, focusValue: .line(line.id, .size), spokenLabel: "Package size")
                    Menu {
                        ForEach(Catalog.packageUnits, id: \.self) { u in
                            Button(u.label) { store.setSizeUnit(line.id, u) }
                        }
                        Divider()
                        Button("Bottle sizes…") { store.usePresetPackages(line.id) }
                    } label: {
                        menuLabel(store.unitLabel(line.sizeUnit), invalid: false)
                    }
                    .fixedSize()
                    .accessibilityLabel("Package unit")
                    .accessibilityIdentifier(id("sizeUnit"))
                }
            }
        }
    }

    @ViewBuilder
    private func amountUnit(dim: UnitDimension) -> some View {
        switch dim {
        case .volume:
            unitText(store.unitLabel(store.settings.displayUnit, pour: true))
        case .count:
            unitText("each")
        case .weight:
            Menu {
                ForEach(Catalog.weightPourUnits, id: \.self) { u in
                    Button(u.label) { store.setAmountUnit(line.id, u) }
                }
            } label: {
                menuLabel(store.unitLabel(line.amountUnit), invalid: false)
            }
            .fixedSize()
            .accessibilityLabel("Pour unit")
            .accessibilityIdentifier(id("amountUnit"))
        }
    }

    private func unitText(_ s: String) -> some View {
        Text(s).font(.subheadline).foregroundStyle(Theme.muted).frame(minWidth: 30, minHeight: 40, alignment: .leading)
            .accessibilityIdentifier(id("unit"))
    }

    private func menuLabel(_ text: String, invalid: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 10)
        .frame(minHeight: 40)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(invalid ? Theme.danger : Theme.line))
    }

    // MARK: - Bindings

    private func id(_ part: String) -> String { "row\(index).\(part)" }

    private func binding(_ field: LineTextField, _ current: String) -> Binding<String> {
        Binding(get: { current }, set: { value in
            let text = String(value.prefix(80))
            store.setLine(line.id, field, field == .name ? text : store.normalizeTyped(text))
        })
    }

    /// The amount as shown in the current oz/mL setting. Typing replaces it in that unit.
    private var amountBinding: Binding<String> {
        Binding(get: { store.displayAmount(line) }, set: { store.setLine(line.id, .amount, store.normalizeTyped($0)) })
    }
}
