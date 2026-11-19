import Foundation

/// What a unit measures. Units can only be converted within the same dimension.
public enum UnitDimension: String, Sendable, CaseIterable {
    case volume, weight, count
}

/// Units Jigger understands. Raw values match the web app's keys so saved data and backups are interchangeable.
///
/// Base units: mL for volume, g for weight, "each" for count. The factors are exact, so a pour
/// costs exactly what was entered. Fluid ounces (`floz`, volume) and ounces by weight (`ozwt`)
/// are different units and never convert into each other.
public enum JiggerUnit: String, Sendable, CaseIterable, Codable {
    case ml, l, floz, g, kg, ozwt, lb, each

    public var dimension: UnitDimension {
        switch self {
        case .ml, .l, .floz: return .volume
        case .g, .kg, .ozwt, .lb: return .weight
        case .each: return .count
        }
    }

    /// Exact number of base units in one of this unit.
    public var factor: Decimal {
        switch self {
        case .ml, .g, .each: return 1
        case .l, .kg: return 1000
        case .floz: return Decimal(string: "29.5735295625", locale: posixLocale)!
        case .ozwt: return Decimal(string: "28.349523125", locale: posixLocale)!
        case .lb: return Decimal(string: "453.59237", locale: posixLocale)!
        }
    }

    public var label: String {
        switch self {
        case .ml: return "mL"
        case .l: return "L"
        case .floz: return "fl oz"
        case .g: return "g"
        case .kg: return "kg"
        case .ozwt: return "oz wt"
        case .lb: return "lb"
        case .each: return "each"
        }
    }

    /// Short label used next to a pour ("oz" rather than "fl oz").
    public var pourLabel: String { self == .floz ? "oz" : label }

    /// Units a pour can be measured in, per dimension (same as the web app's USE_UNITS).
    public static func pourUnits(for dimension: UnitDimension) -> [JiggerUnit] {
        switch dimension {
        case .volume: return [.floz, .ml]
        case .weight: return [.g, .ozwt, .kg, .lb]
        case .count: return [.each]
        }
    }
}

/// Dimension of a unit given as its stored string key, or nil when the key is unknown.
public func dimension(of unitKey: String) -> UnitDimension? {
    JiggerUnit(rawValue: unitKey)?.dimension
}

/// Converts a value to the base unit of its dimension.
public func toBase(_ value: Decimal, _ unit: JiggerUnit) -> Decimal {
    value * unit.factor
}

/// Bar convention used ONLY to show a pour in the other unit (1 oz ≈ 30 mL). Never used for cost.
public let barMillilitersPerOunce: Decimal = 30

let posixLocale = Locale(identifier: "en_US_POSIX")
