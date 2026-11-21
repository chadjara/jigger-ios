import Foundation
import JiggerEngine

/// A labelled figure for display, e.g. in the batch section.
public struct DisplayRow: Equatable, Identifiable, Sendable {
    public enum Tone: Sendable { case plain, good, bad }
    public var label: String
    public var value: String
    public var tone: Tone = .plain
    public var id: String { label }
}

/// Text the UI shows, derived from state and engine results. Keeping it here keeps views free of
/// logic and lets the wording be tested.
extension AppStore {
    public func money(_ value: Decimal?) -> String {
        formatMoney(value, currency: settings.currency, locale: locale)
    }

    /// Money from a typed string, or an em dash when it isn't a valid amount.
    public func money(typed: String) -> String {
        money(parseNumber(typed).value)
    }

    public var currencySymbol: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = settings.currency
        return f.currencySymbol ?? "$"
    }

    public func unitLabel(_ key: String, pour: Bool = false) -> String {
        guard let u = JiggerUnit(rawValue: key) else { return key }
        return pour ? u.pourLabel : u.label
    }

    /// "750 mL", or an em dash when there's no size.
    public func packageLabel(size: String, unit: String) -> String {
        size.isEmpty ? "—" : "\(size) \(unitLabel(unit))"
    }

    /// The amount as shown in the current oz/mL setting. Always derived from what was typed.
    public func displayAmount(_ l: Line) -> String {
        let d = settings.displayUnit
        if dimension(of: l.amountUnit) == .volume && l.amountUnit != d {
            return displayPour(l.amount, from: l.amountUnit, to: d)
        }
        return l.amount
    }

    /// The unit the amount field is shown in.
    public func displayAmountUnit(_ l: Line) -> String {
        dimension(of: resolve(l).sizeUnit) == .volume ? settings.displayUnit : l.amountUnit
    }

    /// "Entered as 2 oz" when the pour is shown converted.
    public func enteredAsNote(_ l: Line) -> String? {
        guard dimension(of: l.amountUnit) == .volume, l.amountUnit != settings.displayUnit, !l.amount.isEmpty else { return nil }
        return "Entered as \(l.amount) \(unitLabel(l.amountUnit, pour: true))"
    }

    public func lineCostText(_ result: LineResult?) -> String {
        guard let result, result.status == .ok else { return "—" }
        return money(result.cost)
    }

    /// "67% of cost", "needs details" or nothing.
    public func lineShareText(_ result: LineResult?, totals: RecipeTotals) -> String {
        guard let result else { return "" }
        switch result.status {
        case .ok:
            if let share = totals.shares[result.id], share > 0 { return formatPct(share, places: 0) + " of cost" }
            return ""
        case .incomplete: return "needs details"
        case .invalid: return ""
        }
    }

    /// True when the pour chip's value equals the amount shown.
    public func isPourSelected(_ l: Line, _ chip: String) -> Bool {
        guard let shown = parseNumber(displayAmount(l)).value, let c = parseNumber(chip).value else { return false }
        return shown == c
    }

    /// Compares the menu price with the suggested price.
    public func comparisonText(_ r: Recipe, _ t: RecipeTotals) -> String? {
        guard let suggested = roundMoney(t.suggestedPrice), t.bevCostPct != nil,
              let menu = parseNumber(r.menuPrice).value, let target = parseNumber(r.targetPct).value else { return nil }
        let diff = menu - suggested
        let absDiff = money(diff < 0 ? -diff : diff)
        let pct = plainString(target)
        if abs(diff) < Decimal(string: "0.005", locale: Locale(identifier: "en_US_POSIX"))! {
            return "Your price matches the suggested price."
        }
        return diff > 0
            ? "Your price is \(absDiff) above the suggested price, so beverage cost lands under your \(pct)% target."
            : "Your price is \(absDiff) below the suggested price, so beverage cost runs over your \(pct)% target."
    }

    /// Batch totals for the chosen number of servings (empty for one serving).
    public func batchRows(_ t: RecipeTotals) -> [DisplayRow] {
        guard t.servings != 1 else { return [] }
        let n = plainString(t.servings)
        var rows = [DisplayRow(label: "Ingredient cost for \(n) drinks", value: money(t.batchCost))]
        if let rev = t.batchRevenue, let profit = t.batchProfit {
            rows.append(DisplayRow(label: "Revenue for \(n) drinks", value: money(rev)))
            rows.append(DisplayRow(label: "Gross profit for \(n) drinks", value: money(profit), tone: profit < 0 ? .bad : .good))
        }
        return rows
    }

    /// Summary line on the collapsed Additional costs section.
    public func extrasSummary(_ r: Recipe, _ t: RecipeTotals) -> String {
        if t.extrasCost > 0 { return "+\(money(t.extrasCost)) per drink" }
        return "None added"
    }

    /// Error for the recipe-wide waste field, or nil.
    public func recipeWasteError(_ r: Recipe) -> String? {
        let w = parseNumber(r.wastePct)
        if w.isInvalid { return "Waste must be a number from 0 to 99." }
        if let v = w.value, v < 0 || v >= 100 { return "Waste must be a number from 0 to 99." }
        return nil
    }

    public func displayDate(_ iso: String) -> String {
        guard let date = isoFormatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// Rewrites a locale's decimal comma as a point, so "24,99" typed on a European keyboard means 24.99.
    /// Leaves input alone in locales that use a decimal point (where commas are thousands separators).
    public func normalizeTyped(_ value: String) -> String {
        sanitizeNumericInput(value, decimalSeparator: locale.decimalSeparator ?? ".", allowFraction: false)
    }

    /// Like `normalizeTyped`, but keeps "/" and spaces so pours like "1 1/2" can be typed.
    public func normalizePour(_ value: String) -> String {
        sanitizeNumericInput(value, decimalSeparator: locale.decimalSeparator ?? ".", allowFraction: true)
    }
}

/// Cleans what's typed or pasted into a number field: a comma decimal becomes a dot (in comma-decimal
/// locales), and anything that can't be part of a number (letters, currency signs, emoji) is dropped.
/// Pours may also keep "/" and spaces for fractions.
public func sanitizeNumericInput(_ value: String, decimalSeparator: String, allowFraction: Bool) -> String {
    let normalized = normalizeDecimalInput(value, decimalSeparator: decimalSeparator)
    let allowed = Set("0123456789.," + (allowFraction ? "/ " : ""))
    return String(normalized.filter { allowed.contains($0) })
}

/// See `AppStore.normalizeTyped`.
public func normalizeDecimalInput(_ value: String, decimalSeparator: String) -> String {
    guard decimalSeparator == "," else { return value }
    return value.replacingOccurrences(of: ",", with: ".")
}
