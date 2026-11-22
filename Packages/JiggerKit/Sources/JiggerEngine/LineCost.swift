import Foundation

/// One ingredient line as typed: every number is the raw string the person entered.
public struct LineInput: Equatable, Sendable {
    public var id: String
    public var price: String
    public var size: String
    /// Package unit key, e.g. "ml", "l", "lb", "each". Unknown keys are reported as errors.
    public var sizeUnit: String
    public var amount: String
    /// Pour unit key, e.g. "floz", "ml", "g", "each".
    public var amountUnit: String
    /// This line's own waste %. Blank means "use the recipe-wide waste %".
    public var wastePct: String

    public init(id: String = "", price: String = "", size: String = "", sizeUnit: String = "ml",
                amount: String = "", amountUnit: String = "floz", wastePct: String = "") {
        self.id = id
        self.price = price
        self.size = size
        self.sizeUnit = sizeUnit
        self.amount = amount
        self.amountUnit = amountUnit
        self.wastePct = wastePct
    }
}

/// Fields that can carry an error message, in display order.
public enum LineField: String, CaseIterable, Sendable {
    case price, size, amount, waste
}

public enum LineStatus: String, Sendable {
    /// All details are present and valid; `cost` is set.
    case ok
    /// Nothing is wrong, but price, size or amount is still blank.
    case incomplete
    /// At least one entry is wrong; see `errors`.
    case invalid
}

public struct LineResult: Equatable, Sendable {
    public var id: String
    public var status: LineStatus
    public var cost: Decimal?
    public var errors: [LineField: String]
    /// Entries that are valid but unusual enough to double-check (the cost still counts).
    public var warnings: [LineField: String] = [:]

    /// Error messages in field order, for display.
    public var errorMessages: [String] { LineField.allCases.compactMap { errors[$0] } }
}

let hundred: Decimal = 100
/// Working precision (decimal places) for percentages. Display rounds to 0–1 places.
let percentPrecision = 28

/// Waste is a yield loss: 10% waste means only 90% of each bottle reaches a glass,
/// so every pour costs its price ÷ 0.90.
func applyWaste(_ cost: Decimal, _ wastePct: Decimal) -> Decimal {
    if wastePct.isZero { return cost }
    return cost / ((hundred - wastePct) / hundred)
}

/// Cost of one ingredient line. Port of the web engine's `lineCost`.
///
/// - Parameter fallbackWaste: the recipe-wide waste % string, used when the line has none.
public func lineCost(_ line: LineInput, fallbackWaste: String? = nil) -> LineResult {
    var errors: [LineField: String] = [:]
    let price = parseNumber(line.price), size = parseNumber(line.size), amount = parseNumber(line.amount)
    var waste = parseNumber(line.wastePct)
    if waste.isBlank { waste = parseNumber(fallbackWaste) }

    if price.isInvalid { errors[.price] = "Enter a price like 24.99" }
    else if let p = price.value, p < 0 { errors[.price] = "Price can’t be negative" }
    if size.isInvalid { errors[.size] = "Enter a size like 750" }
    else if let s = size.value, !(s > 0) { errors[.size] = "Size must be more than 0" }
    if amount.isInvalid { errors[.amount] = "Enter an amount like 1.5 or 1/2" }
    else if let a = amount.value, a < 0 { errors[.amount] = "Amount can’t be negative" }
    if waste.isInvalid { errors[.waste] = "Enter a waste % like 5" }
    else if let w = waste.value, w < 0 || w >= 100 { errors[.waste] = "Waste must be 0–99%" }

    let sizeDim = dimension(of: line.sizeUnit), amountDim = dimension(of: line.amountUnit)
    if sizeDim == nil, errors[.size] == nil { errors[.size] = "Choose a package unit" }
    if amountDim == nil, errors[.amount] == nil { errors[.amount] = "Choose a unit" }
    if let sd = sizeDim, let ad = amountDim, sd != ad {
        errors[.amount] = "Package is sold by \(sd.rawValue); measure the pour by \(sd.rawValue) too"
    }

    if !errors.isEmpty { return LineResult(id: line.id, status: .invalid, cost: nil, errors: errors) }
    guard let p = price.value, let s = size.value, let a = amount.value,
          let sizeUnit = JiggerUnit(rawValue: line.sizeUnit), let amountUnit = JiggerUnit(rawValue: line.amountUnit)
    else { return LineResult(id: line.id, status: .incomplete, cost: nil, errors: [:]) }

    // Multiply first, divide last: keeps results exact whenever they can be.
    let raw = p * toBase(a, amountUnit) / toBase(s, sizeUnit)
    var warnings: [LineField: String] = [:]
    if toBase(a, amountUnit) > toBase(s, sizeUnit) {
        warnings[.amount] = "That’s more than a whole package per drink. Check the pour and the package size."
    }
    if let w = waste.value, w > 50 { warnings[.waste] = "Over 50% waste is unusual. Check the waste %." }
    return LineResult(id: line.id, status: .ok, cost: applyWaste(raw, waste.value ?? 0), errors: [:], warnings: warnings)
}
