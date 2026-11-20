import SwiftUI
import JiggerCore
import JiggerEngine

/// Which input has keyboard focus in the calculator.
enum FieldFocus: Hashable {
    case recipeName
    case line(String, LineTextField)
    case target, menuPrice, servings, recipeWaste
    case extra(String)
}

/// Mix: the costing screen. Ingredients on the left (or top), the tab beside them (or below on iPhone).
struct CalculatorView: View {
    @Environment(AppStore.self) private var store
    @FocusState private var focus: FieldFocus?
    @State private var showPicker = false
    @State private var showReorder = false

    var body: some View {
        let totals = store.draftTotals
        GeometryReader { geo in
            // Side by side when there's room for both columns (iPad), stacked otherwise (iPhone, narrow split view).
            if geo.size.width >= 720 {
                HStack(alignment: .top, spacing: 28) {
                    ScrollView { editor(totals).padding(Theme.gutter) }
                    ScrollView { SummaryCard(totals: totals, focus: $focus).padding(.vertical, Theme.gutter) }
                        .frame(width: Theme.summaryWidth)
                        .padding(.trailing, Theme.gutter)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            editor(totals)
                            SummaryCard(totals: totals, focus: $focus).id("summary")
                        }
                        .padding(Theme.gutter)
                    }
                    .safeAreaInset(edge: .bottom) {
                        CostBar(totals: totals) {
                            focus = nil
                            withAnimation { proxy.scrollTo("summary", anchor: .top) }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Mix")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    store.startNewRecipe()
                    DispatchQueue.main.async { focus = .recipeName }
                } label: {
                    Text("New").font(Theme.body)
                }
                .accessibilityLabel("New recipe")
                .accessibilityIdentifier("newRecipe")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { focus = nil; store.saveRecipe() } label: {
                    Text("Save").font(store.saveStatus.isDirty ? Theme.emphasis : Theme.body)
                }
                .accessibilityLabel("Save recipe")
                .accessibilityIdentifier("saveRecipe")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { focus = nil } label: { Text("Done").font(Theme.emphasis) }
            }
        }
        .sheet(isPresented: $showReorder) { ReorderSheet() }
        .sheet(isPresented: $showPicker) {
            LibraryPicker { itemID in
                showPicker = false
                if let id = store.addLine(fromLibrary: itemID) {
                    DispatchQueue.main.async { focus = .line(id, .amount) }
                }
            }
        }
    }

    @ViewBuilder
    private func editor(_ totals: RecipeTotals) -> some View {
        let draft = store.draft
        VStack(alignment: .leading, spacing: 26) {
            // Masthead: the drink's name, set large on its own rule, with the save state beside the label.
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recipe").capsLabel()
                    Spacer()
                    Text(store.saveStatus.label)
                        .font(Theme.caption)
                        .foregroundStyle(store.saveStatus.isDirty ? Theme.warn : Theme.faint)
                        .accessibilityIdentifier("saveState")
                }
                TextField("Name this drink", text: Binding(get: { store.draft.name }, set: { store.setRecipe(.name, String($0.prefix(80))) }))
                    .font(Theme.heading(32))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focus, equals: .recipeName)
                    .accessibilityLabel("Drink name")
                    .accessibilityIdentifier("recipeName")
                Rectangle()
                    .fill(focus == .recipeName ? Theme.brass : Theme.lineStrong)
                    .frame(height: focus == .recipeName ? 2 : Theme.hairline)
            }

            if draft.isExample {
                HStack(alignment: .top, spacing: 14) {
                    Rectangle().fill(Theme.brass).frame(width: 2)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Example").capsLabel(Theme.brass)
                        Text("This example uses illustrative prices, not real market prices. Edit anything to match what you pay.")
                            .font(Theme.subhead)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Clear example") {
                            store.clearExample()
                            DispatchQueue.main.async { focus = .recipeName }
                        }
                        .buttonStyle(.jSmall())
                        .accessibilityIdentifier("clearExample")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("exampleNotice")
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    RuleHeader(title: "Ingredients", trailing: draft.lines.isEmpty ? nil : String(format: "%02d", draft.lines.count))
                    if draft.lines.count > 1 {
                        Button { focus = nil; showReorder = true } label: {
                            Text("Reorder").font(Theme.futura(12, .bold, relativeTo: .footnote)).tracking(1.2).textCase(.uppercase)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.brass)
                        .fixedSize()
                        .accessibilityIdentifier("reorder")
                    }
                    Picker("Pour unit", selection: Binding(get: { store.settings.displayUnit }, set: { store.setDisplayUnit($0) })) {
                        Text("oz").tag("floz")
                        Text("mL").tag("ml")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 108)
                    .accessibilityIdentifier("unitToggle")
                }
                .padding(.bottom, 4)

                if draft.lines.isEmpty {
                    Text("No ingredients yet. Add the first one to start costing this drink.")
                        .font(Theme.callout)
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, Theme.rowSpacing)
                }
                ForEach(Array(draft.lines.enumerated()), id: \.element.id) { index, line in
                    IngredientRow(line: line, index: index, totals: totals, focus: $focus) { showReorder = true }
                    Hairline()
                }
            }

            addBar

            VStack(spacing: 0) {
                WasteAllRow(focus: $focus)
                AdditionalCostsSection(totals: totals, focus: $focus)
            }
        }
    }

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if let id = store.addLine() { DispatchQueue.main.async { focus = .line(id, .name) } }
                } label: {
                    Label("Add ingredient", systemImage: "plus")
                }
                .buttonStyle(.jPrimary)
                .accessibilityIdentifier("addIngredient")
                Button("From saved") { focus = nil; showPicker = true }
                    .buttonStyle(.jSecondary)
                    .accessibilityLabel("Add from My Ingredients")
                    .accessibilityIdentifier("addFromLibrary")
            }
            .disabled(!store.canAddLine)
            if !store.canAddLine {
                Text("25 ingredients is the maximum for one recipe.")
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("limitNote")
            }
        }
    }
}

/// iPhone-only bar pinned above the tab bar with the two numbers a bartender needs at a glance.
private struct CostBar: View {
    @Environment(AppStore.self) private var store
    let totals: RecipeTotals
    let showSummary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Hairline(color: Theme.lineStrong)
            HStack(alignment: .center, spacing: 22) {
                figure("Per drink", store.money(totals.drinkCost), id: "barDrinkCost", accent: false)
                figure("Charge", totals.suggestedPrice.map { store.money($0) } ?? "—", id: "barSuggested", accent: true)
                Spacer(minLength: 0)
                Button("The tab", action: showSummary)
                    .buttonStyle(.jSmall())
                    .accessibilityLabel("Show summary")
                    .accessibilityIdentifier("showSummary")
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 10)
        }
        .background(Theme.surface)
    }

    private func figure(_ label: String, _ value: String, id: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).capsLabel()
            Text(value)
                .font(Theme.figure(24, relativeTo: .title2))
                .monospacedDigit()
                .foregroundStyle(accent && totals.suggestedPrice != nil ? Theme.brass : Theme.text)
                .accessibilityLabel("\(label): \(value)")
                .accessibilityIdentifier(id)
        }
    }
}

extension DisplayRow.Tone {
    var display: DisplayTone {
        switch self {
        case .plain: return .plain
        case .good: return .good
        case .bad: return .bad
        }
    }
}
