import SwiftUI
import JiggerCore
import JiggerEngine

/// The tab: cost per drink, what to charge, how the menu price performs, batch totals and the cost sheet.
/// Styled like a printed bar ticket: a framed card, perforated between sections, prices on dot leaders.
struct SummaryCard: View {
    @Environment(AppStore.self) private var store
    let totals: RecipeTotals
    var focus: FocusState<FieldFocus?>.Binding

    var body: some View {
        let draft = store.draft
        VStack(alignment: .leading, spacing: 0) {
            // Masthead
            HStack(alignment: .firstTextBaseline) {
                Text("The tab").capsLabel(Theme.brass)
                Spacer(minLength: 12)
                Text(draft.name.isEmpty ? "Untitled drink" : draft.name)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.bottom, 10)
            VStack(spacing: 2) { Hairline(color: Theme.brass); Hairline(color: Theme.brass) }
                .accessibilityHidden(true)

            section(first: true) {
                Text("Cost per drink").capsLabel()
                Text(store.money(totals.drinkCost))
                    .font(Theme.figure(54))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(totals.hasCost ? Theme.text : Theme.faint)
                    .accessibilityIdentifier("drinkCost")
                breakdown(draft)
            }

            section {
                Text("Target beverage cost").font(Theme.subhead).foregroundStyle(Theme.muted)
                HStack(alignment: .bottom, spacing: 12) {
                    JField(label: nil, text: recipeBinding(.targetPct), placeholder: "20", suffix: "%",
                           invalid: totals.targetError != nil, identifier: "targetPct", focus: focus, focusValue: .target,
                           spokenLabel: "Target beverage cost")
                        .frame(width: 96)
                    Spacer(minLength: 8)
                    Stepper("Target beverage cost", onIncrement: { stepTarget(1) }, onDecrement: { stepTarget(-1) })
                        .labelsHidden()
                        .accessibilityIdentifier("targetStepper")
                }
                FieldMessage(text: totals.targetError, identifier: "targetError")
                FieldMessage(text: totals.targetNote, kind: .warning, identifier: "targetNote")
                Text("Suggested menu price").capsLabel().padding(.top, 4)
                Text(totals.suggestedPrice.map { store.money($0) } ?? "—")
                    .font(Theme.figure(36, relativeTo: .title))
                    .monospacedDigit()
                    .foregroundStyle(totals.suggestedPrice == nil ? Theme.faint : Theme.brass)
                    .accessibilityIdentifier("suggestedPrice")
            }

            section {
                inlineField("Your menu price", text: recipeBinding(.menuPrice), prefix: store.currencySymbol,
                            invalid: totals.menuError != nil, identifier: "menuPrice", focusValue: .menuPrice)
                FieldMessage(text: totals.menuError, identifier: "menuError")
                FieldMessage(text: totals.menuBelowCostBy.map { "Below cost: you’d lose \(store.money($0)) on every drink." },
                             kind: .warning, identifier: "menuWarning")
                VStack(spacing: 8) {
                    KeyValueRow(label: "Beverage cost", value: formatPct(totals.bevCostPct), identifier: "bevCostPct")
                    KeyValueRow(label: "Gross profit per drink", value: store.money(totals.grossProfit),
                                tone: profitTone, identifier: "grossProfit")
                    KeyValueRow(label: "Gross margin", value: formatPct(totals.grossMargin), identifier: "grossMargin")
                }
                .padding(.top, 2)
                if let compare = store.comparisonText(draft, totals) {
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle().fill(Theme.brass).frame(width: 2)
                        Text(compare)
                            .font(Theme.note)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("comparison")
                    }
                    .padding(.top, 4)
                }
            }

            section {
                HStack(alignment: .center, spacing: 6) {
                    Text("Servings").capsLabel()
                    Spacer(minLength: 8)
                    ForEach(Catalog.servingChoices, id: \.self) { n in
                        Chip(title: n, selected: draft.servings.trimmingCharacters(in: .whitespaces) == n, identifier: "servings.\(n)") {
                            focus.wrappedValue = nil
                            store.setRecipe(.servings, n)
                        }
                    }
                }
                HStack(alignment: .bottom, spacing: 12) {
                    Text("Or any number").font(Theme.footnote).foregroundStyle(Theme.faint).padding(.bottom, 8)
                    Spacer(minLength: 8)
                    JField(label: nil, text: recipeBinding(.servings), placeholder: "1", keyboard: .numberPad,
                           invalid: totals.servingsError != nil, identifier: "servings", focus: focus, focusValue: .servings,
                           spokenLabel: "Number of servings")
                        .frame(width: 72)
                    Stepper("Servings", onIncrement: { stepServings(1) }, onDecrement: { stepServings(-1) })
                        .labelsHidden()
                        .accessibilityIdentifier("servingsStepper")
                }
                FieldMessage(text: totals.servingsError, identifier: "servingsError")
                let rows = store.batchRows(totals)
                if rows.isEmpty {
                    Text("Pick a number of drinks to cost a batch.").font(Theme.subhead).foregroundStyle(Theme.muted)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            KeyValueRow(label: row.label, value: row.value, tone: row.tone.display, identifier: "batch\(i)")
                        }
                    }
                }
            }

            section {
                Text("Beverage cost is the drink’s cost as a share of its price. Gross margin is what’s left. Both count ingredients and listed additional costs only, never labor, rent, taxes or overhead.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button { printSheet() } label: { Label("Print", systemImage: "printer") }
                        .buttonStyle(.jSmall())
                        .accessibilityIdentifier("printSheet")
                    Button { shareSheet() } label: { Label("Share PDF", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.jSmall(prominent: true))
                        .accessibilityIdentifier("sharePDF")
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(Theme.surface)
        .overlay(Rectangle().inset(by: 5).stroke(Theme.brass.opacity(0.35), lineWidth: Theme.hairline))
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: Theme.hairline))
    }

    // MARK: - Pieces

    private var profitTone: DisplayTone {
        guard let p = totals.grossProfit else { return .plain }
        return p < 0 ? .bad : .good
    }

    /// A ticket section; every one after the first is separated by a dashed perforation.
    private func section<Content: View>(first: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !first { Hairline(color: Theme.lineStrong, dashed: true).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Target % in whole steps, kept within 1–99.
    private func stepTarget(_ delta: Int) {
        focus.wrappedValue = nil
        let current = parseNumber(store.draft.targetPct).value ?? parseNumber(store.settings.targetPct).value ?? 20
        var next = roundHalfUp(current, places: 0) + Decimal(delta)
        next = min(max(next, 1), 99)
        store.setRecipe(.targetPct, plainString(next))
    }

    /// Servings in whole drinks, kept within 1–10,000.
    private func stepServings(_ delta: Int) {
        focus.wrappedValue = nil
        let current = parseNumber(store.draft.servings).value ?? 1
        var next = roundHalfUp(current, places: 0) + Decimal(delta)
        next = min(max(next, 1), 10_000)
        store.setRecipe(.servings, plainString(next))
    }

    private func inlineField(_ label: String, text: Binding<String>, prefix: String? = nil, suffix: String? = nil,
                             invalid: Bool, identifier: String, focusValue: FieldFocus) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            Text(label).font(Theme.subhead).foregroundStyle(Theme.muted).padding(.bottom, 8)
            Spacer(minLength: 8)
            JField(label: nil, text: text, placeholder: prefix == nil ? "" : "0.00", prefix: prefix, suffix: suffix,
                   invalid: invalid, identifier: identifier, focus: focus, focusValue: focusValue, spokenLabel: label)
                .frame(width: 96)
        }
    }

    /// Each ingredient on a dot leader: name ........ share  cost.
    @ViewBuilder
    private func breakdown(_ draft: Recipe) -> some View {
        VStack(spacing: 8) {
            ForEach(draft.lines) { l in
                let res = totals.line(l.id)
                let name = store.resolve(l).name.isEmpty ? "Unnamed ingredient" : store.resolve(l).name
                if let res, res.status == .ok {
                    leaderRow(name, share: totals.shares[l.id], value: store.money(res.cost))
                } else {
                    leaderRow(name, share: nil, value: res?.status == .invalid ? "check entry" : "incomplete", pending: true)
                }
            }
            if totals.extrasCost > 0 {
                leaderRow("Additional costs", share: totals.drinkCost > 0 ? totals.extrasCost / totals.drinkCost * 100 : nil,
                          value: store.money(totals.extrasCost))
            }
        }
        .padding(.top, 4)
    }

    private func leaderRow(_ name: String, share: Decimal?, value: String, pending: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name).font(Theme.subhead).foregroundStyle(Theme.text).lineLimit(1)
            DotLeader()
            if let share, share > 0 {
                Text(formatPct(share, places: 0)).font(Theme.caption).foregroundStyle(Theme.faint).fixedSize()
            }
            Text(value)
                .font(pending ? Theme.note : Theme.futura(14, .bold, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(pending ? Theme.faint : Theme.text)
                .fixedSize()
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
        PDFActions.print(store.costSheet(for: store.draft), store: store)
    }

    private func shareSheet() {
        focus.wrappedValue = nil
        PDFActions.share(store.costSheet(for: store.draft), store: store)
    }
}
