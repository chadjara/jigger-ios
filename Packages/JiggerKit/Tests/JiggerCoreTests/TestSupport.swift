import Foundation
@testable import JiggerCore

/// A store with in-memory storage, en_US money, sequential ids and a ticking clock (so every edit gets a later timestamp).
private var storeCount = 0

func makeStore(_ storage: MemoryStore = MemoryStore()) -> AppStore {
    storeCount += 1
    let prefix = "s\(storeCount)-"
    var n = 0
    var t = Date(timeIntervalSince1970: 1_790_000_000)
    return AppStore(storage: storage, locale: Locale(identifier: "en_US"), autosaveDelay: nil,
                    clock: { t += 1; return t }, makeID: { n += 1; return "\(prefix)\(n)" })
}

extension AppStore {
    /// Cost text for the line at `index` in the draft, as the row shows it.
    func costText(_ index: Int) -> String {
        lineCostText(draftTotals.line(draft.lines[index].id))
    }

    var drinkCostText: String { money(draftTotals.drinkCost) }
    var suggestedText: String { draftTotals.suggestedPrice.map { money($0) } ?? "—" }
    func lineID(_ index: Int) -> String { draft.lines[index].id }
}
