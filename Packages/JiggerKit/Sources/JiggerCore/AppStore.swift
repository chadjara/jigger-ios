import Foundation
import Observation
import JiggerEngine

/// A short message shown at the bottom of the screen, optionally with Undo.
public struct Toast: Identifiable {
    public let id = UUID()
    public let message: String
    public let undo: (() -> Void)?
}

/// The single source of truth for the app. Every change goes through a method here, so views hold
/// no logic and every behaviour is unit-testable without a UI. Mirrors the web app's state handling.
@Observable
public final class AppStore {
    public internal(set) var state: AppState
    public var toast: Toast?
    /// Locale used to display money. Tests pin it to en_US.
    public var locale: Locale

    @ObservationIgnored private let storage: StateStoring
    @ObservationIgnored let clock: () -> Date
    @ObservationIgnored let makeID: () -> String
    /// Seconds to wait before writing changes to disk; nil means only `flush()` writes (tests).
    @ObservationIgnored public var autosaveDelay: Double?
    @ObservationIgnored private var saveScheduled = false
    @ObservationIgnored private var warnedStorage = false

    public init(storage: StateStoring, locale: Locale = .current, autosaveDelay: Double? = 0.25,
                clock: @escaping () -> Date = Date.init, makeID: @escaping () -> String = { UUID().uuidString.lowercased() }) {
        self.storage = storage
        self.locale = locale
        self.autosaveDelay = autosaveDelay
        self.clock = clock
        self.makeID = makeID
        var loaded = storage.load() ?? AppState()
        loaded.library = loaded.library.filter { !$0.id.isEmpty }
        loaded.recipes = loaded.recipes.filter { !$0.id.isEmpty }
        state = loaded
        if state.draft == nil || state.draft?.id.isEmpty == true { state.draft = exampleRecipe() }
    }

    // MARK: - Basics

    public var settings: Settings { state.settings }
    public var library: [LibraryItem] { state.library }
    public var recipes: [Recipe] { state.recipes }
    /// The recipe open in the calculator.
    public var draft: Recipe { state.draft ?? Recipe(id: "") }

    func now() -> String { isoTimestamp(clock()) }

    public func newLine(_ configure: (inout Line) -> Void = { _ in }) -> Line {
        var l = Line(id: makeID(), amountUnit: settings.displayUnit)
        configure(&l)
        return l
    }

    public func newRecipe() -> Recipe {
        let t = now()
        return Recipe(id: makeID(), lines: [newLine()], targetPct: settings.targetPct.isEmpty ? "20" : settings.targetPct,
                      createdAt: t, updatedAt: t)
    }

    /// The Classic Margarita shown on first launch. Prices are illustrative, not market prices.
    public func exampleRecipe() -> Recipe {
        func line(_ name: String, _ price: String, _ size: String, _ unit: String, _ amount: String,
                  amountUnit: String = "floz", custom: Bool = false) -> Line {
            newLine {
                $0.name = name; $0.price = price; $0.size = size; $0.sizeUnit = unit
                $0.amount = amount; $0.amountUnit = amountUnit; $0.pkgMode = custom ? "custom" : "preset"
            }
        }
        var r = newRecipe()
        r.name = "Classic Margarita"
        r.isExample = true
        r.menuPrice = "14"
        r.lines = [
            line("Blanco tequila", "32.00", "750", "ml", "2"),
            line("Triple sec", "14.00", "750", "ml", "1"),
            line("Fresh lime juice", "9.00", "1", "l", "1"),
            line("Agave syrup", "8.50", "500", "ml", "0.5"),
            line("Lime (garnish wheel)", "0.40", "1", "each", "0.25", amountUnit: "each", custom: true),
        ]
        return r
    }

    // MARK: - Library resolution and totals

    public func libraryItem(_ id: String?) -> LibraryItem? {
        guard let id else { return nil }
        return state.library.first { $0.id == id }
    }

    /// A line with its library values filled in (name, package and, unless overridden, price).
    public func resolve(_ l: Line) -> Line {
        guard let it = libraryItem(l.libId) else { return l }
        var r = l
        r.name = it.name; r.size = it.size; r.sizeUnit = it.sizeUnit
        if !l.priceOverride { r.price = it.price }
        return r
    }

    public func engineInput(_ r: Recipe) -> RecipeInput {
        RecipeInput(
            lines: r.lines.map(resolve).map {
                LineInput(id: $0.id, price: $0.price, size: $0.size, sizeUnit: $0.sizeUnit,
                          amount: $0.amount, amountUnit: $0.amountUnit, wastePct: $0.wastePct)
            },
            extras: r.extras, wastePct: r.wastePct, targetPct: r.targetPct, menuPrice: r.menuPrice, servings: r.servings)
    }

    public func totals(_ r: Recipe) -> RecipeTotals { recipeTotals(engineInput(r)) }

    public var draftTotals: RecipeTotals { totals(draft) }

    // MARK: - Mutation plumbing

    func mutateDraft(_ change: (inout Recipe) -> Void) {
        var d = draft
        change(&d)
        d.updatedAt = now()
        state.draft = d
        changed()
    }

    func mutateLine(_ id: String, _ change: (inout Line) -> Void) {
        guard let i = draft.lines.firstIndex(where: { $0.id == id }) else { return }
        mutateDraft { change(&$0.lines[i]) }
    }

    func mutateState(_ change: (inout AppState) -> Void) {
        change(&state)
        changed()
    }

    func changed() {
        guard let delay = autosaveDelay else { return }
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.flush() }
    }

    /// Writes the state to disk now. Called after a short delay automatically, and when the app goes to the background.
    public func flush() {
        saveScheduled = false
        do {
            try storage.save(state)
        } catch {
            if !warnedStorage {
                warnedStorage = true
                showToast("Couldn’t save your changes on this device. Export a backup in Settings to keep them safe.")
            }
        }
    }

    public func showToast(_ message: String, undo: (() -> Void)? = nil) {
        toast = Toast(message: message, undo: undo)
    }

    /// Runs the current toast's Undo action, if any, and dismisses the toast.
    public func undoToast() {
        let action = toast?.undo
        toast = nil
        action?()
    }

    /// Fixes the pour unit after the package unit changes dimension (e.g. a bottle became a bag sold by weight).
    func fixDimension(_ l: inout Line) {
        let d = dimension(of: l.sizeUnit)
        guard dimension(of: l.amountUnit) != d else { return }
        switch d {
        case .volume: l.amountUnit = settings.displayUnit
        case .weight: l.amountUnit = (l.sizeUnit == "ozwt" || l.sizeUnit == "lb") ? "ozwt" : "g"
        default: l.amountUnit = "each"
        }
    }
}

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func isoTimestamp(_ date: Date) -> String { isoFormatter.string(from: date) }
