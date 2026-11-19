import Foundation

// Data model. Field names and string values match the web app's saved state and backup files,
// so a backup exported from the website imports here and the other way round.
// Every number is kept as the exact string the person typed; the engine parses it.

public struct Line: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    /// Set when this line uses an ingredient from My Ingredients (by reference).
    public var libId: String?
    public var name: String
    public var price: String
    public var size: String
    public var sizeUnit: String
    /// "preset" (bottle size menu) or "custom" (free size and unit).
    public var pkgMode: String
    /// True when a linked line has its own price for this recipe; library price changes never overwrite it.
    public var priceOverride: Bool
    public var amount: String
    /// The unit the amount was entered in (the source of truth for cost).
    public var amountUnit: String
    public var wastePct: String

    public init(id: String, libId: String? = nil, name: String = "", price: String = "", size: String = "750",
                sizeUnit: String = "ml", pkgMode: String = "preset", priceOverride: Bool = false,
                amount: String = "", amountUnit: String = "floz", wastePct: String = "") {
        self.id = id
        self.libId = libId
        self.name = name
        self.price = price
        self.size = size
        self.sizeUnit = sizeUnit
        self.pkgMode = pkgMode
        self.priceOverride = priceOverride
        self.amount = amount
        self.amountUnit = amountUnit
        self.wastePct = wastePct
    }

    enum CodingKeys: String, CodingKey {
        case id, libId, name, price, size, sizeUnit, pkgMode, priceOverride, amount, amountUnit, wastePct
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id)
        let lib = c.lenientString(.libId)
        libId = lib.isEmpty ? nil : lib
        name = c.lenientString(.name)
        price = c.lenientString(.price)
        size = c.lenientString(.size)
        sizeUnit = c.lenientString(.sizeUnit, default: "ml")
        pkgMode = c.lenientString(.pkgMode) == "custom" ? "custom" : "preset"
        priceOverride = c.lenientBool(.priceOverride)
        amount = c.lenientString(.amount)
        amountUnit = c.lenientString(.amountUnit, default: "floz")
        wastePct = c.lenientString(.wastePct)
    }
}

public struct Recipe: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var lines: [Line]
    /// Additional per-drink costs keyed by `Catalog.extras` keys.
    public var extras: [String: String]
    public var wastePct: String
    public var targetPct: String
    public var menuPrice: String
    public var servings: String
    /// True only for the built-in Classic Margarita example (illustrative prices).
    public var isExample: Bool
    public var createdAt: String
    public var updatedAt: String

    public init(id: String, name: String = "", lines: [Line] = [], extras: [String: String] = Catalog.emptyExtras,
                wastePct: String = "", targetPct: String = "20", menuPrice: String = "", servings: String = "1",
                isExample: Bool = false, createdAt: String = "", updatedAt: String = "") {
        self.id = id
        self.name = name
        self.lines = lines
        self.extras = extras
        self.wastePct = wastePct
        self.targetPct = targetPct
        self.menuPrice = menuPrice
        self.servings = servings
        self.isExample = isExample
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, lines, extras, wastePct, targetPct, menuPrice, servings, isExample, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id)
        name = c.lenientString(.name)
        lines = (try? c.decodeIfPresent([Line].self, forKey: .lines)) ?? []
        let rawExtras = (try? c.decodeIfPresent([String: LenientString].self, forKey: .extras)) ?? [:]
        extras = Dictionary(uniqueKeysWithValues: Catalog.extras.map { ($0.key, rawExtras[$0.key]?.value ?? "") })
        wastePct = c.lenientString(.wastePct)
        targetPct = c.lenientString(.targetPct, default: "20")
        menuPrice = c.lenientString(.menuPrice)
        servings = c.lenientString(.servings, default: "1")
        isExample = c.lenientBool(.isExample)
        createdAt = c.lenientString(.createdAt)
        updatedAt = c.lenientString(.updatedAt)
    }
}

/// A bottle or ingredient saved in My Ingredients.
public struct LibraryItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var price: String
    public var size: String
    public var sizeUnit: String
    public var createdAt: String
    public var updatedAt: String

    public init(id: String, name: String, price: String, size: String, sizeUnit: String,
                createdAt: String = "", updatedAt: String = "") {
        self.id = id
        self.name = name
        self.price = price
        self.size = size
        self.sizeUnit = sizeUnit
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey { case id, name, price, size, sizeUnit, createdAt, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id)
        name = c.lenientString(.name)
        price = c.lenientString(.price)
        size = c.lenientString(.size)
        sizeUnit = c.lenientString(.sizeUnit, default: "ml")
        createdAt = c.lenientString(.createdAt)
        updatedAt = c.lenientString(.updatedAt)
    }
}

public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case dark, light, system
}

public struct Settings: Codable, Equatable, Sendable {
    public var currency: String = "USD"
    /// "floz" or "ml": how volume pours are shown. Never changes what was entered.
    public var displayUnit: String = "floz"
    public var theme: AppTheme = .dark
    /// Default target beverage cost % for new recipes.
    public var targetPct: String = "20"

    public init() {}

    enum CodingKeys: String, CodingKey { case currency, displayUnit, theme, targetPct }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cur = c.lenientString(.currency, default: "USD")
        currency = Catalog.currencies.contains { $0.code == cur } ? cur : "USD"
        displayUnit = c.lenientString(.displayUnit) == "ml" ? "ml" : "floz"
        theme = AppTheme(rawValue: c.lenientString(.theme)) ?? .dark
        targetPct = c.lenientString(.targetPct, default: "20")
    }
}

/// Everything Jigger stores on the device, as one document.
public struct AppState: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var settings = Settings()
    public var library: [LibraryItem] = []
    public var recipes: [Recipe] = []
    /// The recipe open in the calculator, saved or not.
    public var draft: Recipe?

    public init() {}

    enum CodingKeys: String, CodingKey { case version, settings, library, recipes, draft }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        settings = (try? c.decodeIfPresent(Settings.self, forKey: .settings)) ?? Settings()
        library = (try? c.decodeIfPresent([LibraryItem].self, forKey: .library)) ?? []
        recipes = (try? c.decodeIfPresent([Recipe].self, forKey: .recipes)) ?? []
        draft = try? c.decodeIfPresent(Recipe.self, forKey: .draft)
    }
}

// MARK: - Lenient decoding (backups may hold numbers where strings are expected, or nulls)

struct LenientString: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = "" }
        else if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self), d.isFinite { value = String(d) }
        else if let b = try? c.decode(Bool.self) { value = String(b) }
        else { value = "" }
    }
}

extension KeyedDecodingContainer {
    func lenientString(_ key: Key, default fallback: String = "") -> String {
        guard let v = (try? decodeIfPresent(LenientString.self, forKey: key))?.value, !v.isEmpty else { return fallback }
        return v
    }

    func lenientBool(_ key: Key) -> Bool {
        (try? decodeIfPresent(Bool.self, forKey: key)) ?? false
    }
}
