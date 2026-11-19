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

    /// Fields of a library entry that need fixing (used to outline them in red).
    public func invalidFields(_ item: LibraryItem) -> Set<LibraryTextField> {
        var bad = Set<LibraryTextField>()
        if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { bad.insert(.name) }
        if !(parseNumber(item.price).value.map { $0 >= 0 } ?? false) { bad.insert(.price) }
        if !(parseNumber(item.size).value.map { $0 > 0 } ?? false) { bad.insert(.size) }
        return bad
    }

    /// Adds a new ingredient to My Ingredients. Shows a message and returns false when something is missing.
    @discardableResult
    public func addLibraryItem(name: String, price: String, size: String, sizeUnit: JiggerUnit) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { showToast("Enter a name for the ingredient."); return false }
        guard let p = parseNumber(price).value, p >= 0 else { showToast("Enter the price you pay, like 24.99."); return false }
        guard let s = parseNumber(size).value, s > 0 else { showToast("Enter a package size greater than 0."); return false }
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
        showToast("Deleted \(it.name). Recipes keep its last price.") { [weak self] in
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
        guard let p = parseNumber(value).value, p > 0, p <= 100 else { return false }
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
        showToast("All recipes and ingredients were deleted")
    }
}
