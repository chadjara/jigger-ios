import SwiftUI
import JiggerCore
import JiggerEngine

/// The "menu card": cost per drink, suggested price, menu price analysis, batch scaling and the cost sheet.
struct SummaryCard: View {
    @Environment(AppStore.self) private var store
    let totals: RecipeTotals
    var focus: FocusState<FieldFocus?>.Binding
    @State private var shareItem: SharedFile?
    @State private var exporting = false

    var body: some View {
        let draft = store.draft
        VStack(alignment: .leading, spacing: 0) {
            section {
                caption("Cost per drink")
                Text(store.money(totals.drinkCost))
                    .font(Theme.figure(44))
                    .monospacedDigit()
                    .foregroundStyle(totals.hasCost ? Theme.text : Theme.faint)
                    .accessibilityIdentifier("drinkCost")
                breakdown(draft)
            }

            section {
                inlineField("Target beverage cost", text: recipeBinding(.targetPct), suffix: "%", invalid: totals.targetError != nil,
                            identifier: "targetPct", focusValue: .target)
                errorText(totals.targetError, id: "targetError")
                caption("Suggested menu price")
                Text(totals.suggestedPrice.map { store.money($0) } ?? "—")
                    .font(Theme.figure(30, relativeTo: .title))
                    .monospacedDigit()
                    .foregroundStyle(totals.suggestedPrice == nil ? Theme.faint : Theme.text)
                    .accessibilityIdentifier("suggestedPrice")
            }

            section {
                inlineField("Your menu price", text: recipeBinding(.menuPrice), prefix: store.currencySymbol, invalid: totals.menuError != nil,
                            identifier: "menuPrice", focusValue: .menuPrice)
                errorText(totals.menuError, id: "menuError")
                VStack(spacing: 6) {
                    KeyValueRow(label: "Beverage cost", value: formatPct(totals.bevCostPct), identifier: "bevCostPct")
                    KeyValueRow(label: "Gross profit per drink", value: store.money(totals.grossProfit),
                                tone: profitTone, identifier: "grossProfit")
                    KeyValueRow(label: "Gross margin", value: formatPct(totals.grossMargin), identifier: "grossMargin")
                }
                if let compare = store.comparisonText(draft, totals) {
                    Text(compare)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .accessibilityIdentifier("comparison")
                }
            }

            section {
                HStack(alignment: .center) {
                    Text("Servings").font(.subheadline).foregroundStyle(Theme.muted)
                    Spacer()
                    ForEach(Catalog.servingChoices, id: \.self) { n in
                        Chip(title: n, selected: draft.servings.trimmingCharacters(in: .whitespaces) == n, identifier: "servings.\(n)") {
                            focus.wrappedValue = nil
                            store.setRecipe(.servings, n)
                        }
                    }
                }
                HStack {
                    Spacer()
                    JField(label: nil, text: recipeBinding(.servings), placeholder: "1", keyboard: .numberPad,
                           invalid: totals.servingsError != nil, identifier: "servings", focus: focus, focusValue: .servings,
                           spokenLabel: "Number of servings")
                        .frame(width: 120)
                }
                errorText(totals.servingsError, id: "servingsError")
                let rows = store.batchRows(totals)
                if rows.isEmpty {
                    Text("Pick a number of servings to cost a batch.").font(.subheadline).foregroundStyle(Theme.muted)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            KeyValueRow(label: row.label, value: row.value, tone: row.tone.display, identifier: "batch\(i)")
                        }
                    }
                }
                Text("Beverage cost is the drink’s cost as a share of its price. Gross margin is what’s left. Both count ingredient and additional costs only, not labor, rent, taxes or overhead.")
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
                HStack(spacing: 8) {
                    Button { printSheet() } label: { Label("Print", systemImage: "printer") }
                        .buttonStyle(.jSmall())
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("printSheet")
                    Button { shareSheet() } label: { Label("Share PDF", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.jSmall())
                        .frame(maxWidth: .infinity)
                        .disabled(exporting)
                        .accessibilityIdentifier("sharePDF")
                }
            }
        }
        .padding(20)
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.brass.opacity(0.45)))
        .padding(6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line))
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url]).ignoresSafeArea()
        }
    }

    // MARK: - Pieces

    private var profitTone: DisplayTone {
        guard let p = totals.grossProfit else { return .plain }
        return p < 0 ? .bad : .good
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
    }

    @ViewBuilder
    private func errorText(_ message: String?, id: String) -> some View {
        if let message {
            Text(message).font(.footnote).foregroundStyle(Theme.danger).accessibilityIdentifier(id)
        }
    }

    private func inlineField(_ label: String, text: Binding<String>, prefix: String? = nil, suffix: String? = nil,
                             invalid: Bool, identifier: String, focusValue: FieldFocus) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.muted)
            Spacer()
            JField(label: nil, text: text, placeholder: prefix == nil ? "" : "0.00", prefix: prefix, suffix: suffix,
                   invalid: invalid, identifier: identifier, focus: focus, focusValue: focusValue, spokenLabel: label)
                .frame(width: 120)
        }
    }

    @ViewBuilder
    private func breakdown(_ draft: Recipe) -> some View {
        VStack(spacing: 7) {
            ForEach(draft.lines) { l in
                let res = totals.line(l.id)
                let name = store.resolve(l).name.isEmpty ? "Unnamed ingredient" : store.resolve(l).name
                if let res, res.status == .ok {
                    shareRow(name, store.money(res.cost), share: totals.shares[l.id] ?? 0)
                } else {
                    HStack {
                        Text(name).lineLimit(1)
                        Spacer()
                        Text(res?.status == .invalid ? "check entry" : "incomplete").italic().foregroundStyle(Theme.faint)
                    }
                    .font(.subheadline)
                }
            }
            if totals.extrasCost > 0 {
                shareRow("Additional costs", store.money(totals.extrasCost),
                         share: totals.drinkCost > 0 ? totals.extrasCost / totals.drinkCost * 100 : 0)
            }
        }
        .padding(.top, 6)
    }

    private func shareRow(_ name: String, _ value: String, share: Decimal) -> some View {
        let fraction = min(max(NSDecimalNumber(decimal: share).doubleValue / 100, 0), 1)
        return VStack(spacing: 3) {
            HStack {
                Text(name).lineLimit(1)
                Spacer()
                Text(value).monospacedDigit()
            }
            .font(.subheadline)
            Capsule().fill(Theme.sunken).frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { g in Capsule().fill(Theme.brass).frame(width: g.size.width * fraction) }
                }
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func recipeBinding(_ field: RecipeTextField) -> Binding<String> {
        Binding(get: {
            switch field {
            case .targetPct: return store.draft.targetPct
            case .menuPrice: return store.draft.menuPrice
            case .servings: return store.draft.servings
            case .wastePct: return store.draft.wastePct
            case .name: return store.draft.name
            }
        }, set: { store.setRecipe(field, store.normalizeTyped($0)) })
    }

    // MARK: - Cost sheet

    private func printSheet() {
        focus.wrappedValue = nil
        let sheet = store.costSheet(for: store.draft)
        if !CostSheetPrinter.print(sheet) {
            store.showToast("Printing isn’t available on this device. Use Share PDF to save or send the cost sheet.")
        }
    }

    private func shareSheet() {
        focus.wrappedValue = nil
        exporting = true
        defer { exporting = false }
        do {
            let url = try CostSheetPDF.writeTemporaryFile(store.costSheet(for: store.draft))
            shareItem = SharedFile(url: url)
        } catch {
            store.showToast("Couldn’t create the PDF. Please try again.")
        }
    }
}
