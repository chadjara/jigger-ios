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

/// The main screen: ingredients on the left (or top), the cost summary beside them (or below on iPhone).
struct CalculatorView: View {
    @Environment(AppStore.self) private var store
    @FocusState private var focus: FieldFocus?
    @State private var showPicker = false

    var body: some View {
        let totals = store.draftTotals
        GeometryReader { geo in
            // Side by side when there's room for both columns (iPad), stacked otherwise (iPhone, narrow split view).
            if geo.size.width >= 720 {
                HStack(alignment: .top, spacing: 24) {
                    ScrollView { editor(totals).padding(Theme.gutter) }
                    ScrollView { SummaryCard(totals: totals, focus: $focus).padding(.vertical, Theme.gutter) }
                        .frame(width: Theme.summaryWidth)
                        .padding(.trailing, Theme.gutter)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
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
        .navigationTitle("Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("New Recipe") {
                    store.startNewRecipe()
                    DispatchQueue.main.async { focus = .recipeName }
                }
                .accessibilityIdentifier("newRecipe")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { focus = nil; store.saveRecipe() }
                    .fontWeight(store.saveStatus.isDirty ? .semibold : .regular)
                    .accessibilityIdentifier("saveRecipe")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name this drink", text: Binding(get: { store.draft.name }, set: { store.setRecipe(.name, String($0.prefix(80))) }))
                    .font(Theme.heading(30))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focus, equals: .recipeName)
                    .accessibilityLabel("Drink name")
                    .accessibilityIdentifier("recipeName")
                Rectangle().fill(focus == .recipeName ? Theme.brass : Theme.line).frame(height: 1)
                Text(store.saveStatus.label)
                    .font(.footnote)
                    .foregroundStyle(store.saveStatus.isDirty ? Theme.warn : Theme.faint)
                    .accessibilityIdentifier("saveState")
            }

            if draft.isExample {
                HStack(alignment: .center, spacing: 12) {
                    Text("This example uses illustrative prices, not real market prices. Edit anything to match what you pay.")
                        .font(.subheadline)
                    Spacer(minLength: 0)
                    Button("Clear example") {
                        store.clearExample()
                        DispatchQueue.main.async { focus = .recipeName }
                    }
                    .buttonStyle(.jSmall())
                    .accessibilityIdentifier("clearExample")
                }
                .padding(12)
                .background(Theme.brassSoft, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(alignment: .leading) { Rectangle().fill(Theme.brass).frame(width: 3) }
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("exampleNotice")
            }

            HStack {
                SectionHeader(title: "Ingredients")
                Spacer()
                Picker("Pour unit", selection: Binding(get: { store.settings.displayUnit }, set: { store.setDisplayUnit($0) })) {
                    Text("oz").tag("floz")
                    Text("mL").tag("ml")
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .accessibilityIdentifier("unitToggle")
            }

            if draft.lines.isEmpty {
                Text("No ingredients yet. Add the first one to start costing this drink.")
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .card(padding: 28)
            }
            ForEach(Array(draft.lines.enumerated()), id: \.element.id) { index, line in
                IngredientRow(line: line, index: index, totals: totals, focus: $focus)
            }

            addBar

            AdditionalCostsSection(totals: totals, focus: $focus)
        }
    }

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if let id = store.addLine() { DispatchQueue.main.async { focus = .line(id, .name) } }
                } label: {
                    Label("Add ingredient", systemImage: "plus")
                }
                .buttonStyle(.jPrimary)
                .accessibilityIdentifier("addIngredient")
                Button("From My Ingredients") { focus = nil; showPicker = true }
                    .buttonStyle(.jSecondary)
                    .accessibilityIdentifier("addFromLibrary")
            }
            .disabled(!store.canAddLine)
            if !store.canAddLine {
                Text("25 ingredients is the maximum for one recipe.")
                    .font(.footnote)
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
        HStack(spacing: 18) {
            figure("Cost per drink", store.money(totals.drinkCost), id: "barDrinkCost")
            figure("Suggested price", totals.suggestedPrice.map { store.money($0) } ?? "—", id: "barSuggested")
            Spacer()
            Button("Summary", action: showSummary).buttonStyle(.jSmall())
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func figure(_ label: String, _ value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(Theme.muted)
            Text(value).font(Theme.figure(20, relativeTo: .title3)).monospacedDigit()
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
