import Foundation
import JiggerEngine

/// Fixed lists the app offers. Same values as the web app.
public enum Catalog {
    public static let maxLines = 25

    public struct Currency: Identifiable, Sendable {
        public let code: String
        public let name: String
        public var id: String { code }
    }

    public static let currencies: [Currency] = [
        .init(code: "USD", name: "US dollar"), .init(code: "CAD", name: "Canadian dollar"),
        .init(code: "MXN", name: "Mexican peso"), .init(code: "EUR", name: "Euro"),
        .init(code: "GBP", name: "British pound"), .init(code: "AUD", name: "Australian dollar"),
        .init(code: "NZD", name: "New Zealand dollar"), .init(code: "CHF", name: "Swiss franc"),
    ]

    public struct PackagePreset: Hashable, Identifiable, Sendable {
        public let size: String
        public let unit: String
        public var id: String { "\(size)|\(unit)" }
        public var label: String { "\(size) \(JiggerUnit(rawValue: unit)?.label ?? unit) bottle" }
    }

    /// Common bottle sizes.
    public static let packagePresets: [PackagePreset] = [
        .init(size: "50", unit: "ml"), .init(size: "200", unit: "ml"), .init(size: "375", unit: "ml"),
        .init(size: "500", unit: "ml"), .init(size: "750", unit: "ml"), .init(size: "1", unit: "l"),
        .init(size: "1.75", unit: "l"),
    ]

    public static func isPreset(size: String, unit: String) -> Bool {
        packagePresets.contains { $0.size == size && $0.unit == unit }
    }

    /// One-tap pour amounts per display unit.
    public static func pours(for displayUnit: String) -> [String] {
        displayUnit == "ml"
            ? ["7.5", "15", "22.5", "30", "37.5", "45", "60", "90"]
            : ["0.25", "0.5", "0.75", "1", "1.25", "1.5", "2", "3"]
    }

    public struct Extra: Identifiable, Sendable {
        public let key: String
        public let label: String
        public var id: String { key }
    }

    /// Additional per-drink costs, in display order.
    public static let extras: [Extra] = [
        .init(key: "garnish", label: "Garnish"), .init(key: "napkins", label: "Napkin"),
        .init(key: "straws", label: "Straw"), .init(key: "cups", label: "Cup or container"),
        .init(key: "other", label: "Other prep"),
    ]

    public static var emptyExtras: [String: String] {
        Dictionary(uniqueKeysWithValues: extras.map { ($0.key, "") })
    }

    /// Package units offered for custom sizes and library items.
    public static let packageUnits: [JiggerUnit] = [.ml, .l, .floz, .g, .kg, .ozwt, .lb, .each]

    /// Weight pour units.
    public static let weightPourUnits: [JiggerUnit] = [.g, .ozwt, .kg, .lb]

    /// Servings quick picks for batch scaling.
    public static let servingChoices = ["1", "10", "25", "100"]
}
