import Foundation

/// Shows a volume pour in the other display unit using the bar convention (1 oz ≈ 30 mL).
///
/// Always converts from the SOURCE value the person typed, so toggling oz/mL any number of
/// times never drifts. Returns the input unchanged when it can't or needn't be converted.
public func displayPour(_ value: String, from: String, to: String) -> String {
    guard let v = parseNumber(value).value else { return value }
    if from == to { return value }
    let out: Decimal
    switch (from, to) {
    case ("floz", "ml"): out = roundHalfUp(v * barMillilitersPerOunce, places: 1)
    case ("ml", "floz"): out = roundHalfUp(v / barMillilitersPerOunce, places: 2)
    default: return value
    }
    return plainString(out)
}
