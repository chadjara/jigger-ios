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
