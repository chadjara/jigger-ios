import Foundation

// Display helpers. Rounding happens only here, never inside a calculation.

/// Rounds half-up (away from zero on a tie) to `places` decimal places.
public func roundHalfUp(_ value: Decimal, places: Int) -> Decimal {
    var input = value, result = Decimal()
    NSDecimalRound(&result, &input, places, .plain)
    return result
}

/// Money rounded for display: 2 places, half-up.
public func roundMoney(_ value: Decimal?) -> Decimal? {
    value.map { roundHalfUp($0, places: 2) }
}

/// Formats money as currency, rounded half-up to 2 places. nil shows as an em dash.
public func formatMoney(_ value: Decimal?, currency: String = "USD", locale: Locale = Locale(identifier: "en_US")) -> String {
    guard var rounded = roundMoney(value) else { return "—" }
    if rounded.isZero { rounded = 0 } // never show "-$0.00"
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.locale = locale
    f.currencyCode = currency
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f.string(from: NSDecimalNumber(decimal: rounded)) ?? fixed(rounded, places: 2)
}

/// Formats a percentage with a fixed number of places, rounded half-up: 26.3888 -> "26.4%".
public func formatPct(_ value: Decimal?, places: Int = 1) -> String {
    guard let value else { return "—" }
    return fixed(value, places: places) + "%"
}

/// Rounds half-up and prints with exactly `places` decimals, locale-independent: (2.5, 2) -> "2.50".
public func fixed(_ value: Decimal, places: Int) -> String {
    let rounded = roundHalfUp(value, places: places)
    var s = plainString(rounded)
    guard places > 0 else { return s }
    if let dot = s.firstIndex(of: ".") {
        let decimals = s.distance(from: dot, to: s.endIndex) - 1
        if decimals < places { s += String(repeating: "0", count: places - decimals) }
    } else {
        s += "." + String(repeating: "0", count: places)
    }
    return s
}

/// Locale-independent string for a Decimal: "0.9", "1", "1.67". Matches decimal.js `toString()`
/// for the magnitudes Jigger deals with.
public func plainString(_ value: Decimal) -> String {
    var s = NSDecimalNumber(decimal: value).description(withLocale: posixLocale)
    if s == "-0" { s = "0" }
    return s
}
