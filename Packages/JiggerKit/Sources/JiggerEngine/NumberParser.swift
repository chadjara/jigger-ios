import Foundation

/// The result of parsing something a person typed.
public enum ParsedNumber: Equatable, Sendable {
    /// Nothing was entered (the field is blank).
    case blank
    /// Something was entered, but it isn't a number we understand.
    case invalid
    case value(Decimal)

    public var value: Decimal? {
        if case let .value(v) = self { return v }
        return nil
    }

    public var isInvalid: Bool { self == .invalid }
    public var isBlank: Bool { self == .blank }
}

/// Parses a typed number exactly like the web engine's `parse`.
///
/// Accepts "24.99", "$24.99", "1,000", ".5", "1/2" and "1 1/2". Commas are thousands separators.
/// Blank input is `.blank`; anything else that isn't a number is `.invalid`. Never throws.
public func parseNumber(_ input: String?) -> ParsedNumber {
    guard let input else { return .blank }
    var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
    // Drop trailing currency symbols and spaces, then one leading currency symbol.
    while let last = s.last, currencySymbols.contains(last) || last.isWhitespace { s.removeLast() }
    if let first = s.first, currencySymbols.contains(first) { s.removeFirst() }
    s = s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return .blank }

    // Mixed number: "1 1/2"
    let words = s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    if words.count == 2, isDigits(words[0]) {
        let parts = words[1].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2, isDigits(parts[0]), isDigits(parts[1]) {
            let whole = decimal(words[0]), num = decimal(parts[0]), den = decimal(parts[1])
            return den.isZero ? .invalid : .value(whole + num / den)
        }
    }

    // Fraction: "1/2", ".5/2"
    let parts = s.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    if parts.count == 2, isUnsignedDecimal(parts[0]), isUnsignedDecimal(parts[1]) {
        let num = decimal(parts[0]), den = decimal(parts[1])
        return den.isZero ? .invalid : .value(num / den)
    }

    guard isPlainNumber(s) else { return .invalid }
    return .value(decimal(s))
}

private let currencySymbols: Set<Character> = ["$", "€", "£", "¥"]

private func isDigits<S: StringProtocol>(_ s: S) -> Bool {
    !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber }
}

/// Matches `\d*\.?\d+`: "5", ".5", "1.5" (but not "5.").
private func isUnsignedDecimal(_ s: String) -> Bool {
    let pieces = s.split(separator: ".", omittingEmptySubsequences: false)
    switch pieces.count {
    case 1: return isDigits(pieces[0])
    case 2: return (pieces[0].isEmpty || isDigits(pieces[0])) && isDigits(pieces[1])
    default: return false
    }
}

/// Matches `-?(\d+\.?\d*|\.\d+)`: "5", "5.", "5.25", ".5", "-2".
private func isPlainNumber(_ s: String) -> Bool {
    var body = Substring(s)
    if body.first == "-" { body = body.dropFirst() }
    let pieces = body.split(separator: ".", omittingEmptySubsequences: false)
    switch pieces.count {
    case 1: return isDigits(pieces[0])
    case 2:
        if pieces[0].isEmpty { return isDigits(pieces[1]) }
        return isDigits(pieces[0]) && (pieces[1].isEmpty || isDigits(pieces[1]))
    default: return false
    }
}

/// Converts an already-validated numeric string to Decimal.
private func decimal(_ s: String) -> Decimal {
    var t = s
    if t.hasSuffix(".") { t.removeLast() }
    if t.hasPrefix("-.") { t = "-0." + t.dropFirst(2) } else if t.hasPrefix(".") { t = "0" + t }
    return Decimal(string: t, locale: posixLocale) ?? 0
}
