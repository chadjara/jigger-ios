import Foundation

/// Beverage cost percentages shown in the cost sheet's price ladder.
public let priceLadderTargets: [Decimal] = [18, 20, 22, 25]

public struct PriceLadderStep: Equatable, Sendable {
    public var targetPct: Decimal
    /// Menu price needed to hit `targetPct` beverage cost: drink cost ÷ target.
    public var price: Decimal
}

/// Menu prices at each beverage cost target. Empty when there's no cost to price.
public func priceLadder(_ totals: RecipeTotals, targets: [Decimal] = priceLadderTargets) -> [PriceLadderStep] {
    guard totals.hasCost else { return [] }
    return targets.filter { $0 > 0 && $0 <= 100 }.map {
        PriceLadderStep(targetPct: $0, price: totals.drinkCost / ($0 / hundred))
    }
}

/// The costed line that contributes most to the drink cost (first one wins a tie), or nil if none is costed.
public func biggestCostDriver(_ totals: RecipeTotals) -> LineResult? {
    var best: LineResult?
    for l in totals.lines where l.status == .ok {
        if let c = l.cost, c > (best?.cost ?? -1) { best = l }
    }
    return best
}

/// What a unit cost is quoted per.
public enum UnitCostBasis: Sendable {
    case fluidOunce, tenMilliliters, weightOunce, each

    /// Short label, e.g. "$1.13 / oz".
    public var label: String {
        switch self {
        case .fluidOunce: return "oz"
        case .tenMilliliters: return "10 mL"
        case .weightOunce: return "oz wt"
        case .each: return "each"
        }
    }

    /// How many base units (mL, g or each) one basis unit holds. Exact.
    var baseQuantity: Decimal {
        switch self {
        case .fluidOunce: return JiggerUnit.floz.factor
        case .tenMilliliters: return 10
        case .weightOunce: return JiggerUnit.ozwt.factor
        case .each: return 1
        }
    }
}

public struct UnitCost: Equatable, Sendable {
    /// Exact (unrounded) cost of one basis unit.
    public var amount: Decimal
    public var basis: UnitCostBasis
}

/// Cost of one pour unit of a package: per fluid ounce (or per 10 mL when pours are shown in mL),
/// per ounce by weight, or per each. Nil when price, size or unit isn't usable. Multiplies before dividing.
public func unitCost(price: String, size: String, sizeUnit: String, volumeDisplayUnit: String = "floz") -> UnitCost? {
    guard let p = parseNumber(price).value, p >= 0,
          let s = parseNumber(size).value, s > 0,
          let unit = JiggerUnit(rawValue: sizeUnit) else { return nil }
    let basis: UnitCostBasis
    switch unit.dimension {
    case .volume: basis = volumeDisplayUnit == "ml" ? .tenMilliliters : .fluidOunce
    case .weight: basis = .weightOunce
    case .count: basis = .each
    }
    return UnitCost(amount: p * basis.baseQuantity / toBase(s, unit), basis: basis)
}
