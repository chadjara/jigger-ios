import Foundation
import JiggerEngine

public enum LibraryTextField: Sendable {
    case name, price, size
}

extension AppStore {
    /// Saved ingredients matching a search, A–Z.
    public func filteredLibrary(_ query: String) -> [LibraryItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state.library
            .filter { q.isEmpty || $0.name.lowercased().contains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// How many saved recipes use this ingredient.
    public func usageCount(_ itemID: String) -> Int {
        state.recipes.filter { $0.lines.contains { $0.libId == itemID } }.count
    }

    /// The saved ingredient identical to this one, if any: same name (ignoring case and spacing)
    /// and the same package. Different sizes of the same bottle are different ingredients.
    public func identicalLibraryItem(name: String, size: String, sizeUnit: String, excluding id: String? = nil) -> LibraryItem? {
        let key = normalizedName(name)
        guard !key.isEmpty else { return nil }
        let wantedSize = parseNumber(size).value
        return state.library.first { it in
            it.id != id && normalizedName(it.name) == key && it.sizeUnit == sizeUnit
                && (parseNumber(it.size).value.map { $0 == wantedSize } ?? (it.size == size))
        }
    }

    func normalizedName(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Fields of a library entry that need fixing (used to outline them in red).
    /// A name that duplicates another saved ingredient with the same package counts as invalid.
    public func invalidFields(_ item: LibraryItem) -> Set<LibraryTextField> {
        var bad = Set<LibraryTextField>()
        if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || identicalLibraryItem(name: item.name, size: item.size, sizeUnit: item.sizeUnit, excluding: item.id) != nil {
            bad.insert(.name)
        }
        if !(parseNumber(item.price).value.map { $0 >= 0 } ?? false) { bad.insert(.price) }
        if !(parseNumber(item.size).value.map { $0 > 0 } ?? false) { bad.insert(.size) }
        return bad
    }

    /// A message for each field that's missing or wrong, for the My Ingredients editor (new or existing item).
    public func libraryFieldMessages(name: String, price: String, size: String, sizeUnit: String,
                                     excluding id: String? = nil) -> [LibraryTextField: String] {
        var m: [LibraryTextField: String] = [:]
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { m[.name] = "Enter a name" }
        else if identicalLibraryItem(name: name, size: size, sizeUnit: sizeUnit, excluding: id) != nil {
            m[.name] = "Already in My Ingredients with this package size"
        }
        let p = parseNumber(price)
        if p.isBlank { m[.price] = "Enter the price you pay" }
        else if p.isInvalid { m[.price] = "Enter a price like 24.99" }
        else if let v = p.value, v < 0 { m[.price] = "Price can’t be negative" }
        let sz = parseNumber(size)
        if sz.isBlank { m[.size] = "Enter the package size" }
        else if sz.isInvalid { m[.size] = "Enter a size like 750" }
        else if let v = sz.value, !(v > 0) { m[.size] = "Size must be more than 0" }
        return m
    }

    /// Adds a new ingredient to My Ingredients. Shows a message and returns false when something is missing.
    @discardableResult
    public func addLibraryItem(name: String, price: String, size: String, sizeUnit: JiggerUnit) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { showToast("Enter a name"); return false }
        guard let p = parseNumber(price).value, p >= 0 else { showToast("Enter the price you pay"); return false }
        guard let s = parseNumber(size).value, s > 0 else { showToast("Enter a package size"); return false }
        guard identicalLibraryItem(name: trimmed, size: size, sizeUnit: sizeUnit.rawValue) == nil else {
            showToast("Already in My Ingredients"); return false
        }
        let t = now()
        let item = LibraryItem(id: makeID(), name: trimmed, price: price, size: size, sizeUnit: sizeUnit.rawValue, createdAt: t, updatedAt: t)
        mutateState { $0.library.append(item) }
        showToast("Added \(trimmed)")
        return true
    }

    /// Edits a saved ingredient. Recipes that use it recalculate, except lines with their own custom price.
    public func updateLibraryItem(_ id: String, _ field: LibraryTextField, _ value: String) {
        guard let i = state.library.firstIndex(where: { $0.id == id }) else { return }
        let t = now()
        mutateState { s in
            switch field {
            case .name: s.library[i].name = value
            case .price: s.library[i].price = value
            case .size: s.library[i].size = value
            }
            s.library[i].updatedAt = t
        }
    }

    public func setLibrarySizeUnit(_ id: String, _ unit: JiggerUnit) {
        guard let i = state.library.firstIndex(where: { $0.id == id }) else { return }
        var s = state
        s.library[i].sizeUnit = unit.rawValue
        s.library[i].updatedAt = now()
        // Keep every linked line's pour unit compatible with the new package unit.
        func fix(_ r: inout Recipe) {
            for j in r.lines.indices where r.lines[j].libId == id {
                r.lines[j].sizeUnit = unit.rawValue
                fixDimension(&r.lines[j])
            }
        }
        for k in s.recipes.indices { fix(&s.recipes[k]) }
        if var d = s.draft { fix(&d); s.draft = d }
        mutateState { $0 = s }
    }

    /// Deletes a saved ingredient. Recipes keep its last values as their own, and the whole change can be undone.
    public func deleteLibraryItem(_ id: String) {
        guard let it = libraryItem(id) else { return }
        let snapshot = state
        var s = state
        func detach(_ r: inout Recipe) {
            for j in r.lines.indices where r.lines[j].libId == id {
                var l = resolve(r.lines[j])
                l.libId = nil
                l.priceOverride = false
                l.pkgMode = Catalog.isPreset(size: it.size, unit: it.sizeUnit) ? "preset" : "custom"
                r.lines[j] = l
            }
        }
        for k in s.recipes.indices { detach(&s.recipes[k]) }
        if var d = s.draft { detach(&d); s.draft = d }
        s.library.removeAll { $0.id == id }
        mutateState { $0 = s }
        showToast("Deleted \(it.name) · recipes keep its price") { [weak self] in
            guard let self else { return }
            let settings = self.state.settings
            self.mutateState { $0 = snapshot; $0.settings = settings }
        }
    }

    // MARK: - Settings

    public func setCurrency(_ code: String) {
        guard Catalog.currencies.contains(where: { $0.code == code }) else { return }
        mutateState { $0.settings.currency = code }
    }

    /// Sets the default target % for new recipes. Returns false (and keeps the old value) when invalid.
    @discardableResult
    public func setDefaultTarget(_ value: String) -> Bool {
        guard parseNumber(value).value != nil, checkTargetPct(value).error == nil else { return false }
        mutateState { $0.settings.targetPct = value.trimmingCharacters(in: .whitespacesAndNewlines) }
        return true
    }

    public func setTheme(_ theme: AppTheme) {
        mutateState { $0.settings.theme = theme }
    }

    /// Deletes every saved recipe and ingredient, keeping settings.
    public func resetAll() {
        mutateState { s in
            s.library = []
            s.recipes = []
        }
        state.draft = newRecipe()
        flush()
        showToast("All recipes and ingredients deleted")
    }
}
