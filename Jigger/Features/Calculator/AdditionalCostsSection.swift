import SwiftUI
import JiggerCore
import JiggerEngine

/// Folded away by default: garnish, napkin, straw, cup, other prep, and the recipe-wide waste %.
struct AdditionalCostsSection: View {
    @Environment(AppStore.self) private var store
    let totals: RecipeTotals
    var focus: FocusState<FieldFocus?>.Binding
    @State private var expanded = false

    var body: some View {
        let draft = store.draft
        VStack(alignment: .leading, spacing: 0) {
            Hairline(color: Theme.lineStrong)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Additional costs").font(Theme.emphasis).foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Text(store.extrasSummary(draft, totals))
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("extrasSummary")
                    Text(expanded ? "−" : "+")
                        .font(Theme.futura(20, .medium, relativeTo: .title3))
                        .foregroundStyle(Theme.brass)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("additionalCosts")

            if expanded {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Per-drink costs that aren’t ingredients. Leave a field empty if you already added that item as an ingredient above, so it isn’t counted twice.")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 18, alignment: .leading)],
                              alignment: .leading, spacing: 16) {
                        ForEach(Catalog.extras) { extra in
                            JField(label: extra.label, text: extraBinding(extra.key), placeholder: "0.00", prefix: store.currencySymbol,
                                   invalid: totals.extrasErrors[extra.key] != nil, identifier: "extra.\(extra.key)",
                                   focus: focus, focusValue: .extra(extra.key))
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        JField(label: "Waste & spillage", text: wasteBinding, placeholder: "0", suffix: "%",
                               invalid: store.recipeWasteError(draft) != nil, identifier: "recipeWaste",
                               focus: focus, focusValue: .recipeWaste)
                            .frame(width: 130)
                        if let err = store.recipeWasteError(draft) {
                            Text(err).font(Theme.footnote).foregroundStyle(Theme.danger)
                        }
                        Text("The share of each bottle that never reaches a glass: spills, overpours, spoilage. At 10%, every pour costs its price ÷ 0.90. It applies to every ingredient without its own waste %.")
                            .font(Theme.footnote)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 20)
                .transition(.opacity)
            }
            Hairline(color: Theme.lineStrong)
        }
    }

    private func extraBinding(_ key: String) -> Binding<String> {
        Binding(get: { store.draft.extras[key] ?? "" }, set: { store.setExtra(key, store.normalizeTyped($0)) })
    }

    private var wasteBinding: Binding<String> {
        Binding(get: { store.draft.wastePct }, set: { store.setRecipe(.wastePct, store.normalizeTyped($0)) })
    }
}
