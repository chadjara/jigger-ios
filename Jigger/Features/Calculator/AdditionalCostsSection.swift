import SwiftUI
import JiggerCore
import JiggerEngine

/// Collapsed by default: garnish, napkin, straw, cup, other prep, and the recipe-wide waste %.
struct AdditionalCostsSection: View {
    @Environment(AppStore.self) private var store
    let totals: RecipeTotals
    var focus: FocusState<FieldFocus?>.Binding
    @State private var expanded = false

    var body: some View {
        let draft = store.draft
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Per-drink costs that aren’t ingredients. Leave a field empty if you already added that item as an ingredient above, so it isn’t counted twice.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(Catalog.extras) { extra in
                        JField(label: extra.label, text: extraBinding(extra.key), placeholder: "0.00", prefix: store.currencySymbol,
                               invalid: totals.extrasErrors[extra.key] != nil, identifier: "extra.\(extra.key)",
                               focus: focus, focusValue: .extra(extra.key))
                    }
                }
                JField(label: "Waste & spillage", text: wasteBinding, placeholder: "0", suffix: "%",
                       invalid: store.recipeWasteError(draft) != nil, identifier: "recipeWaste",
                       focus: focus, focusValue: .recipeWaste)
                    .frame(maxWidth: 160)
                if let err = store.recipeWasteError(draft) {
                    Text(err).font(.footnote).foregroundStyle(Theme.danger)
                }
                Text("Waste is the share of each bottle that never reaches a glass (spills, overpours, spoilage). At 10%, every pour costs its price ÷ 0.90. It applies to every ingredient that doesn’t have its own waste % set.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.top, 12)
        } label: {
            HStack {
                Text("Additional costs").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text(store.extrasSummary(draft, totals))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("extrasSummary")
            }
        }
        .accessibilityIdentifier("additionalCosts")
        .card(padding: 16)
    }

    private func extraBinding(_ key: String) -> Binding<String> {
        Binding(get: { store.draft.extras[key] ?? "" }, set: { store.setExtra(key, store.normalizeTyped($0)) })
    }

    private var wasteBinding: Binding<String> {
        Binding(get: { store.draft.wastePct }, set: { store.setRecipe(.wastePct, store.normalizeTyped($0)) })
    }
}
