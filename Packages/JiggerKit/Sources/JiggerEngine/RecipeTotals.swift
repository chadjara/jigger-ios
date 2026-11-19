import Foundation

/// A recipe as typed. Every number is the raw string the person entered.
public struct RecipeInput: Equatable, Sendable {
    public var lines: [LineInput]
    /// Additional per-drink costs (garnish, napkin, straw…), keyed by extra name.
    public var extras: [String: String]
    /// Recipe-wide waste %, used by lines without their own.
    public var wastePct: String
    public var targetPct: String
    public var menuPrice: String
    public var servings: String

    public init(lines: [LineInput] = [], extras: [String: String] = [:], wastePct: String = "",
                targetPct: String = "", menuPrice: String = "", servings: String = "") {
        self.lines = lines
        self.extras = extras
        self.wastePct = wastePct
        self.targetPct = targetPct
        self.menuPrice = menuPrice
        self.servings = servings
    }
}

/// Every figure for a recipe. Values are exact (unrounded) Decimals, or nil when they can't be computed.
public struct RecipeTotals: Equatable, Sendable {
    public var lines: [LineResult]
    /// Each costed line's share of the drink cost, in percent, keyed by line id.
    public var shares: [String: Decimal]
    public var ingredientCost: Decimal
    public var extrasCost: Decimal
    public var drinkCost: Decimal
    /// True when at least one line is costed or an additional cost is above zero.
    public var hasCost: Bool
    public var counted: Int
    public var incomplete: Int
    public var invalid: Int
    public var extrasErrors: [String: String]

    public var suggestedPrice: Decimal?
    public var targetError: String?
    public var bevCostPct: Decimal?
    public var grossProfit: Decimal?
    public var grossMargin: Decimal?
    public var menuError: String?

    public var servings: Decimal
    public var servingsError: String?
    public var batchCost: Decimal
    public var batchRevenue: Decimal?
    public var batchProfit: Decimal?

    public func line(_ id: String) -> LineResult? { lines.first { $0.id == id } }
}

/// Full recipe totals. Port of the web engine's `recipeTotals`. Never divides by zero, never throws.
public func recipeTotals(_ recipe: RecipeInput) -> RecipeTotals {
    let lines = recipe.lines.map { lineCost($0, fallbackWaste: recipe.wastePct) }
    var ingredientCost: Decimal = 0
    var counted = 0, incomplete = 0, invalid = 0
    for l in lines {
        switch l.status {
        case .ok: ingredientCost += l.cost ?? 0; counted += 1
        case .incomplete: incomplete += 1
        case .invalid: invalid += 1
        }
    }

    var extrasErrors: [String: String] = [:]
    var extrasCost: Decimal = 0
    for key in recipe.extras.keys.sorted() {
        let p = parseNumber(recipe.extras[key])
        if p.isInvalid || (p.value.map { $0 < 0 } ?? false) {
            extrasErrors[key] = "Enter an amount like 0.10"
            continue
        }
        if let v = p.value { extrasCost += v }
    }
    let drinkCost = ingredientCost + extrasCost
    let hasCost = counted > 0 || extrasCost > 0

    let target = parseNumber(recipe.targetPct)
    var targetError: String?, suggestedPrice: Decimal?
    if target.isInvalid { targetError = "Enter a percentage like 20" }
    else if let t = target.value, !(t > 0) || t > 100 { targetError = "Target must be between 0 and 100%" }
    else if let t = target.value, hasCost { suggestedPrice = drinkCost / (t / hundred) }

    let menu = parseNumber(recipe.menuPrice)
    var menuError: String?, bevCostPct: Decimal?, grossProfit: Decimal?, grossMargin: Decimal?
    var validMenu: Decimal?
    if menu.isInvalid { menuError = "Enter a price like 14.00" }
    else if let m = menu.value, !(m > 0) { menuError = "Menu price must be more than 0" }
    else if let m = menu.value {
        validMenu = m
        if hasCost {
            // Percentages carry a fixed working precision (28 places, far beyond the 1 shown). Foundation's
            // Decimal holds ~38 digits, so without it bev% + margin could come out as 99.999…9.
            let bev = roundHalfUp(drinkCost / m * hundred, places: percentPrecision)
            bevCostPct = bev
            grossProfit = m - drinkCost
            // (price − cost) / price × 100, written as 100 − bev% (algebraically identical), so beverage
            // cost % + gross margin is always exactly 100, as on the website.
            grossMargin = hundred - bev
        }
    }

    var servings: Decimal = 1
    var servingsError: String?
    switch parseNumber(recipe.servings) {
    case .blank: break
    case let .value(v) where v > 0: servings = v
    default: servingsError = "Servings must be more than 0"
    }
    let batchCost = drinkCost * servings
    let batchRevenue = validMenu.map { $0 * servings }

    var shares: [String: Decimal] = [:]
    if drinkCost > 0 {
        for l in lines where l.status == .ok { shares[l.id] = (l.cost ?? 0) / drinkCost * hundred }
    }

    return RecipeTotals(
        lines: lines, shares: shares, ingredientCost: ingredientCost, extrasCost: extrasCost,
        drinkCost: drinkCost, hasCost: hasCost, counted: counted, incomplete: incomplete, invalid: invalid,
        extrasErrors: extrasErrors, suggestedPrice: suggestedPrice, targetError: targetError,
        bevCostPct: bevCostPct, grossProfit: grossProfit, grossMargin: grossMargin, menuError: menuError,
        servings: servings, servingsError: servingsError, batchCost: batchCost,
        batchRevenue: batchRevenue, batchProfit: batchRevenue.map { $0 - batchCost })
}
