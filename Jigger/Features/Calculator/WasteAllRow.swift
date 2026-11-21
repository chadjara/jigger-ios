import SwiftUI
import JiggerCore
import JiggerEngine

/// One waste % for the whole recipe, set once instead of on every ingredient.
/// Ingredients with their own % keep it; a one-tap action brings them all in line.
struct WasteAllRow: View {
    @Environment(AppStore.self) private var store
    var focus: FocusState<FieldFocus?>.Binding

    var body: some View {
        let draft = store.draft
        let error = store.recipeWasteError(draft)
        let own = store.linesWithOwnWaste
        let pct = draft.wastePct.trimmingCharacters(in: .whitespaces)

        VStack(alignment: .leading, spacing: 10) {
            Hairline(color: Theme.lineStrong)
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Waste · all ingredients").capsLabel(Theme.text)
                    Text("Spills, overpours and spoilage. Applies to every ingredient without its own %.")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                JField(label: nil, text: binding, placeholder: "0", suffix: "%", invalid: error != nil,
                       identifier: "recipeWaste", focus: focus, focusValue: .recipeWaste,
                       spokenLabel: "Waste percent for all ingredients")
                    .frame(width: 84)
            }
            FieldMessage(text: error, identifier: "recipeWasteError")
            if error == nil, let w = parseNumber(draft.wastePct).value, w > 50 {
                FieldMessage(text: "Over 50% waste is unusual. Check the waste %.", kind: .warning)
            }
            if own > 0 {
                HStack(alignment: .center, spacing: 12) {
                    Text(own == 1 ? "1 ingredient uses its own %" : "\(own) ingredients use their own %")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.faint)
                    Spacer(minLength: 8)
                    Button(pct.isEmpty ? "Clear their %" : "Use \(pct)% for all") {
                        focus.wrappedValue = nil
                        store.applyRecipeWasteToAll()
                    }
                    .buttonStyle(.jSmall())
                    .disabled(error != nil)
                    .accessibilityIdentifier("applyWasteToAll")
                }
            }
        }
        .padding(.bottom, 16)
    }

    private var binding: Binding<String> {
        Binding(get: { store.draft.wastePct }, set: { store.setRecipe(.wastePct, store.normalizeTyped($0)) })
    }
}
