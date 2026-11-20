import SwiftUI
import JiggerCore
import JiggerEngine

/// One numbered line on the spec sheet: what you paid, the package, the pour, and what that pour costs.
struct IngredientRow: View {
    @Environment(AppStore.self) private var store
    let line: Line
    let index: Int
    let totals: RecipeTotals
    var focus: FocusState<FieldFocus?>.Binding
    /// Opens the drag-to-reorder list.
    let onReorder: () -> Void

    var body: some View {
        let resolved = store.resolve(line)
        let item = store.libraryItem(line.libId)
        let result = totals.line(line.id)
        let errors = result?.errors ?? [:]
        let dim = dimension(of: resolved.sizeUnit) ?? .volume
        let displayName = resolved.name.isEmpty ? "ingredient" : resolved.name

        HStack(alignment: .top, spacing: 14) {
            // Line number, in brass (red when something needs fixing). Tap it to move the line.
            Menu {
                ForEach(LineMove.allCases, id: \.self) { move in
                    Button { focus.wrappedValue = nil; store.moveLine(line.id, move) } label: {
                        Label(move.label, systemImage: move.systemImage)
                    }
                    .disabled(!store.canMoveLine(line.id, move))
                }
                Divider()
                Button { focus.wrappedValue = nil; onReorder() } label: { Label("Reorder…", systemImage: "line.3.horizontal") }
            } label: {
                VStack(spacing: 3) {
                    Text(String(format: "%02d", index + 1))
                        .font(Theme.futura(13, .bold, relativeTo: .footnote))
                        .monospacedDigit()
                        .foregroundStyle(errors.isEmpty ? Theme.brass : Theme.danger)
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                }
                .frame(width: 26, height: 44)
                .contentShape(Rectangle())
            }
            .padding(.top, 10)
            .accessibilityLabel("Ingredient \(index + 1) options")
            .accessibilityHint("Move this ingredient")
            .accessibilityIdentifier(id("order"))

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 0) {
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

                HStack(alignment: .bottom, spacing: 16) {
                    JField(label: "Price paid", text: binding(.price, resolved.price), placeholder: "0.00",
                           prefix: store.currencySymbol, invalid: errors[.price] != nil, identifier: id("price"),
                           focus: focus, focusValue: .line(line.id, .price))
                        .frame(width: 112)
                    packageField(resolved: resolved, linked: item != nil, invalid: errors[.size] != nil)
                }

                HStack(alignment: .bottom, spacing: 16) {
                    HStack(alignment: .bottom, spacing: 8) {
                        JField(label: "Pour", text: amountBinding, placeholder: dim == .count ? "1/2" : "0",
                               keyboard: .numbersAndPunctuation, invalid: errors[.amount] != nil, identifier: id("amount"),
                               focus: focus, focusValue: .line(line.id, .amount), spokenLabel: "Used per drink")
                            .frame(width: 112)
                        amountUnit(dim: dim)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(store.lineCostText(result))
                            .font(Theme.figure(24, relativeTo: .title2))
                            .monospacedDigit()
                            .foregroundStyle(result?.status == .ok ? Theme.text : Theme.faint)
                            .accessibilityIdentifier(id("cost"))
                        Text(store.lineShareText(result, totals: totals))
                            .font(Theme.caption)
                            .foregroundStyle(Theme.faint)
                    }
                }

                if dim == .volume {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Catalog.pours(for: store.settings.displayUnit), id: \.self) { pour in
                                Chip(title: pour, selected: store.isPourSelected(line, pour), identifier: id("pour.\(pour)")) {
                                    store.tapPour(line.id, pour)
                                }
                            }
                        }
                    }
                    .accessibilityLabel("Common pours in \(store.unitLabel(store.settings.displayUnit, pour: true))")
                }

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let item {
                            if line.priceOverride {
                                Text("Custom price in this recipe")
                                    .font(Theme.caption).foregroundStyle(Theme.brass)
                                    .accessibilityIdentifier(id("tag"))
                                Button("Use saved \(store.money(typed: item.price))") { store.revertPrice(line.id) }
                                    .font(Theme.futura(12, .bold, relativeTo: .caption))
                                    .foregroundStyle(Theme.brass)
                                    .underline()
                                    .accessibilityIdentifier(id("revertPrice"))
                            } else {
                                Text("From My Ingredients")
                                    .font(Theme.caption).foregroundStyle(Theme.brass)
                                    .accessibilityIdentifier(id("tag"))
                            }
                        }
                        if let note = store.enteredAsNote(line) {
                            Text(note).font(Theme.note).foregroundStyle(Theme.muted).accessibilityIdentifier(id("enteredAs"))
                        }
                    }
                    Spacer(minLength: 0)
                    JField(label: "Waste", text: binding(.wastePct, line.wastePct),
                           placeholder: store.draft.wastePct.isEmpty ? "0" : store.draft.wastePct, suffix: "%",
                           invalid: errors[.waste] != nil, identifier: id("waste"),
                           focus: focus, focusValue: .line(line.id, .wastePct),
                           spokenLabel: "Waste percent for this ingredient", compact: true)
                        .frame(width: 76)
                }

                if let result, !result.errorMessages.isEmpty {
                    Text(result.errorMessages.joined(separator: ". "))
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(id("error"))
                }
            }
        }
        .padding(.vertical, Theme.rowSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("row\(index)")
    }

    // MARK: - Pieces

    @ViewBuilder
    private func packageField(resolved: Line, linked: Bool, invalid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Package").capsLabel()
            if linked {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.packageLabel(size: resolved.size, unit: resolved.sizeUnit))
                        .font(Theme.body)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    Hairline(color: Theme.lineStrong, dashed: true)
                }
                .accessibilityElement(children: .combine)
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
                    MenuFieldLabel(text: Catalog.isPreset(size: line.size, unit: line.sizeUnit)
                                   ? "\(store.packageLabel(size: line.size, unit: line.sizeUnit)) bottle"
                                   : store.packageLabel(size: line.size, unit: line.sizeUnit), invalid: invalid)
                }
                .accessibilityLabel("Package size")
                .accessibilityIdentifier(id("package"))
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    JField(label: nil, text: binding(.size, line.size), placeholder: "Size", invalid: invalid,
                           identifier: id("size"), focus: focus, focusValue: .line(line.id, .size), spokenLabel: "Package size")
                    Menu {
                        ForEach(Catalog.packageUnits, id: \.self) { u in
                            Button(u.label) { store.setSizeUnit(line.id, u) }
                        }
                        Divider()
                        Button("Bottle sizes…") { store.usePresetPackages(line.id) }
                    } label: {
                        MenuFieldLabel(text: store.unitLabel(line.sizeUnit))
                    }
                    .frame(width: 84)
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
                MenuFieldLabel(text: store.unitLabel(line.amountUnit))
            }
            .frame(width: 76)
            .accessibilityLabel("Pour unit")
            .accessibilityIdentifier(id("amountUnit"))
        }
    }

    private func unitText(_ s: String) -> some View {
        Text(s).font(Theme.callout).foregroundStyle(Theme.muted)
            .padding(.bottom, 8)
            .accessibilityIdentifier(id("unit"))
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

extension LineMove {
    var systemImage: String {
        switch self {
        case .top: return "arrow.up.to.line"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .bottom: return "arrow.down.to.line"
        }
    }
}
