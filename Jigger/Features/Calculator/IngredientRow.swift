import SwiftUI
import JiggerCore
import JiggerEngine

/// One numbered line on the spec sheet: name, pour and package at a glance, and what the pour costs.
/// Tap to edit it in a form; touch and hold for duplicate, move and delete.
struct IngredientRow: View {
    @Environment(AppStore.self) private var store
    let line: Line
    let index: Int
    let totals: RecipeTotals
    let open: () -> Void
    /// Opens the drag-to-reorder list.
    let onReorder: () -> Void

    var body: some View {
        let resolved = store.resolve(line)
        let item = store.libraryItem(line.libId)
        let result = totals.line(line.id)
        let hasError = !(result?.errors.isEmpty ?? true)
        let name = resolved.name

        HStack(alignment: .center, spacing: 14) {
            Text(String(format: "%02d", index + 1))
                .font(Theme.futura(13, .bold, relativeTo: .footnote))
                .monospacedDigit()
                .foregroundStyle(hasError ? Theme.danger : Theme.brass)
                .frame(width: 24, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(name.isEmpty ? "New ingredient" : name)
                    .font(Theme.body)
                    .foregroundStyle(name.isEmpty ? Theme.faint : Theme.text)
                    .lineLimit(1)
                    .accessibilityIdentifier(id("name"))
                Text(detail(resolved, result))
                    .font(Theme.caption)
                    .foregroundStyle(hasError ? Theme.danger : Theme.muted)
                    .lineLimit(2)
                    .accessibilityIdentifier(hasError ? id("error") : id("detail"))
                if item != nil {
                    Text(line.priceOverride ? "Custom price · My Ingredients" : "From My Ingredients")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.brass)
                        .accessibilityIdentifier(id("tag"))
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(store.lineCostText(result))
                    .font(Theme.figure(22, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(result?.status == .ok ? Theme.text : Theme.faint)
                    .accessibilityIdentifier(id("cost"))
                Text(store.lineShareText(result, totals: totals))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.faint)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.faint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .contextMenu { menu }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Ingredient \(index + 1), \(name.isEmpty ? "new ingredient" : name), \(store.lineCostText(result))")
        .accessibilityHint("Opens the ingredient. Touch and hold for more options.")
        .accessibilityAction(named: "Edit", open)
        .accessibilityIdentifier("row\(index)")
    }

    @ViewBuilder
    private var menu: some View {
        Button(action: open) { Label("Edit", systemImage: "pencil") }
        Button { store.duplicateLine(line.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            .disabled(!store.canAddLine)
        Divider()
        ForEach(LineMove.allCases, id: \.self) { move in
            Button { store.moveLine(line.id, move) } label: { Label(move.label, systemImage: move.systemImage) }
                .disabled(!store.canMoveLine(line.id, move))
        }
        Button(action: onReorder) { Label("Reorder…", systemImage: "line.3.horizontal") }
        Divider()
        Button(role: .destructive) { store.removeLine(line.id) } label: { Label("Remove", systemImage: "trash") }
    }

    /// "2 oz · $24.99 for 750 mL", or what's still needed / wrong.
    private func detail(_ resolved: Line, _ result: LineResult?) -> String {
        if let result, let message = result.errorMessages.first { return message }
        var missing: [String] = []
        if resolved.price.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("price") }
        if resolved.size.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("package size") }
        if line.amount.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("pour") }
        if !missing.isEmpty { return "Add the " + missing.joined(separator: ", ") }
        let unit = store.unitLabel(store.displayAmountUnit(line), pour: true)
        return "\(store.displayAmount(line)) \(unit) · \(store.money(typed: resolved.price)) for \(store.packageLabel(size: resolved.size, unit: resolved.sizeUnit))"
    }

    private func id(_ part: String) -> String { "row\(index).\(part)" }
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
