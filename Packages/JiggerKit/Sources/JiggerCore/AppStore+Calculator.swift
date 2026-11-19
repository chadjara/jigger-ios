import Foundation
import JiggerEngine

/// Text fields on an ingredient line.
public enum LineTextField: Sendable {
    case name, price, size, amount, wastePct
}

/// Recipe-level text fields in the calculator.
public enum RecipeTextField: Sendable {
    case name, targetPct, menuPrice, servings, wastePct
}

public enum SaveToLibraryOutcome: Equatable, Sendable {
    case saved, needsName, needsPrice, needsSize
}

public enum SaveStatus: Equatable, Sendable {
    /// Nothing worth saving yet.
    case empty
    case notSavedYet
    case saved
    case unsavedChanges

    public var label: String {
        switch self {
        case .empty: return ""
        case .notSavedYet: return "Not saved yet"
        case .saved: return "Saved"
        case .unsavedChanges: return "Unsaved changes"
        }
    }

    public var isDirty: Bool { self == .notSavedYet || self == .unsavedChanges }
}

extension AppStore {
    // MARK: - Ingredient lines

    public var canAddLine: Bool { draft.lines.count < Catalog.maxLines }

    /// Adds a blank line. Returns its id, or nil at the 25-ingredient limit.
    @discardableResult
    public func addLine() -> String? {
        guard canAddLine else { return nil }
        let l = newLine()
        mutateDraft { $0.lines.append(l) }
        return l.id
    }

    /// Adds a line that uses a saved ingredient by reference. Returns its id, or nil at the limit.
    @discardableResult
    public func addLine(fromLibrary itemID: String) -> String? {
        guard canAddLine, let it = libraryItem(itemID) else { return nil }
        var l = newLine { $0.libId = it.id; $0.name = it.name; $0.size = it.size; $0.sizeUnit = it.sizeUnit }
        fixDimension(&l)
        mutateDraft { $0.lines.append(l) }
        return l.id
    }

    public func removeLine(_ id: String) {
        guard let i = draft.lines.firstIndex(where: { $0.id == id }) else { return }
        let removed = draft.lines[i]
        let name = resolve(removed).name
        mutateDraft { $0.lines.remove(at: i) }
        showToast("Removed \(name.isEmpty ? "ingredient" : name)") { [weak self] in
            guard let self else { return }
            self.mutateDraft { $0.lines.insert(removed, at: min(i, $0.lines.count)) }
        }
    }

    public func setLine(_ id: String, _ field: LineTextField, _ value: String) {
        let linked = libraryItem(draft.lines.first { $0.id == id }?.libId) != nil
        let displayUnit = settings.displayUnit
        mutateLine(id) { l in
            switch field {
            case .name: l.name = value
            case .price:
                l.price = value
                if linked { l.priceOverride = true }
            case .size: l.size = value
            case .wastePct: l.wastePct = value
            case .amount:
                l.amount = value
                // Typing a volume makes the unit currently shown the source.
                if dimension(of: l.amountUnit) == .volume { l.amountUnit = displayUnit }
            }
        }
    }

    /// One-tap pour chip: sets the amount in the unit currently shown.
    public func tapPour(_ id: String, _ amount: String) {
        let displayUnit = settings.displayUnit
        mutateLine(id) { $0.amount = amount; $0.amountUnit = displayUnit }
    }

    public func choosePreset(_ id: String, _ preset: Catalog.PackagePreset) {
        mutateLine(id) { l in
            l.size = preset.size; l.sizeUnit = preset.unit
            fixDimension(&l)
        }
    }

    /// Switches a line from the bottle-size menu to a free size and unit.
    public func useCustomPackage(_ id: String) {
        mutateLine(id) { $0.pkgMode = "custom" }
    }

    /// Switches back to the bottle-size menu, defaulting to 750 mL if the current size isn't a preset.
    public func usePresetPackages(_ id: String) {
        mutateLine(id) { l in
            l.pkgMode = "preset"
            if !Catalog.isPreset(size: l.size, unit: l.sizeUnit) { l.size = "750"; l.sizeUnit = "ml" }
            fixDimension(&l)
        }
    }

    public func setSizeUnit(_ id: String, _ unit: JiggerUnit) {
        mutateLine(id) { l in
            l.sizeUnit = unit.rawValue
            fixDimension(&l)
        }
    }

    public func setAmountUnit(_ id: String, _ unit: JiggerUnit) {
        mutateLine(id) { $0.amountUnit = unit.rawValue }
    }

    /// Saves a line's bottle to My Ingredients and links the line to it.
    @discardableResult
    public func saveLineToLibrary(_ id: String) -> SaveToLibraryOutcome {
        guard let l = draft.lines.first(where: { $0.id == id }) else { return .needsName }
        let name = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { showToast("Name the ingredient before saving it."); return .needsName }
        guard let p = parseNumber(l.price).value, p >= 0 else { showToast("Add a valid price before saving it."); return .needsPrice }
        guard let s = parseNumber(l.size).value, s > 0, dimension(of: l.sizeUnit) != nil else {
            showToast("Add a valid package size before saving it."); return .needsSize
        }
        let t = now()
        let item = LibraryItem(id: makeID(), name: name, price: l.price, size: l.size, sizeUnit: l.sizeUnit, createdAt: t, updatedAt: t)
        state.library.append(item)
        mutateLine(id) { $0.libId = item.id; $0.priceOverride = false }
        showToast("Saved \(name) to My Ingredients")
        return .saved
    }

    /// Drops a linked line's custom price so it follows My Ingredients again.
    public func revertPrice(_ id: String) {
        mutateLine(id) { $0.priceOverride = false; $0.price = "" }
    }

    // MARK: - Recipe fields

    public func setRecipe(_ field: RecipeTextField, _ value: String) {
        mutateDraft { r in
            switch field {
            case .name: r.name = value
            case .targetPct: r.targetPct = value
            case .menuPrice: r.menuPrice = value
            case .servings: r.servings = value
            case .wastePct: r.wastePct = value
            }
        }
    }

    public func setExtra(_ key: String, _ value: String) {
        mutateDraft { $0.extras[key] = value }
    }

    public func setDisplayUnit(_ unit: String) {
        guard unit == "floz" || unit == "ml" else { return }
        mutateState { $0.settings.displayUnit = unit }
    }

    // MARK: - Saving and switching recipes

    private func comparable(_ r: Recipe) -> Recipe {
        var c = r
        c.createdAt = ""; c.updatedAt = ""; c.isExample = false
        return c
    }

    func hasContent(_ r: Recipe) -> Bool {
        !r.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || r.lines.contains { !$0.name.isEmpty || !$0.price.isEmpty || !$0.amount.isEmpty || $0.libId != nil }
    }

    public var saveStatus: SaveStatus {
        if let saved = state.recipes.first(where: { $0.id == draft.id }) {
            return comparable(saved) == comparable(draft) ? .saved : .unsavedChanges
        }
        return hasContent(draft) ? .notSavedYet : .empty
    }

    public func saveRecipe() {
        mutateDraft { r in
            if r.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { r.name = "Untitled drink" }
            r.isExample = false
        }
        let copy = draft
        if let i = state.recipes.firstIndex(where: { $0.id == copy.id }) { state.recipes[i] = copy } else { state.recipes.append(copy) }
        flush()
        showToast("Saved \(copy.name)")
    }

    func replaceDraft(_ next: Recipe, message: String) {
        let prev = draft
        let wasDirty = saveStatus.isDirty
        state.draft = next
        changed()
        if wasDirty && hasContent(prev) {
            let name = prev.name.isEmpty ? "the previous drink" : prev.name
            showToast("\(message). Unsaved changes to \(name) were set aside.") { [weak self] in
                self?.state.draft = prev
                self?.changed()
            }
        } else {
            showToast(message)
        }
    }

    public func startNewRecipe() {
        replaceDraft(newRecipe(), message: "Started a new recipe")
    }

    /// Replaces the example with a blank recipe (no undo needed: the example can't be lost).
    public func clearExample() {
        state.draft = newRecipe()
        changed()
    }

    public func openRecipe(_ id: String) {
        guard draft.id != id, let r = state.recipes.first(where: { $0.id == id }) else { return }
        replaceDraft(r, message: "Opened \(r.name)")
    }

    public func duplicateRecipe(_ id: String) {
        guard let r = state.recipes.first(where: { $0.id == id }) else { return }
        var c = r
        c.id = makeID()
        c.name = "\(r.name) (copy)"
        c.lines = r.lines.map { var l = $0; l.id = makeID(); return l }
        c.createdAt = now(); c.updatedAt = c.createdAt
        mutateState { $0.recipes.append(c) }
        showToast("Duplicated as \(c.name)")
    }

    public func deleteRecipe(_ id: String) {
        guard let i = state.recipes.firstIndex(where: { $0.id == id }) else { return }
        let r = state.recipes[i]
        mutateState { $0.recipes.remove(at: i) }
        showToast("Deleted \(r.name)") { [weak self] in
            self?.mutateState { $0.recipes.insert(r, at: min(i, $0.recipes.count)) }
        }
    }

    /// Saved recipes matching a search of recipe or ingredient names, most recently updated first.
    public func filteredRecipes(_ query: String) -> [Recipe] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state.recipes
            .filter { r in q.isEmpty || r.name.lowercased().contains(q) || r.lines.contains { resolve($0).name.lowercased().contains(q) } }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
