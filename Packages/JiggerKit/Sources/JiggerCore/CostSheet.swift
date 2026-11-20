import Foundation
import JiggerEngine

/// A printable document (cost sheet, recipe book or price list) as self-contained HTML.
/// The app turns it into a paginated PDF for AirPrint, Save to Files and Share.
public struct CostSheet {
    public let html: String
    public let title: String
    /// Ending of the file name, e.g. "cost-sheet" gives "classic-margarita-cost-sheet.pdf".
    public var fileSuffix: String = "cost-sheet"

    public init(html: String, title: String, fileSuffix: String = "cost-sheet") {
        self.html = html
        self.title = title
        self.fileSuffix = fileSuffix
    }

    /// Suggested PDF file name, e.g. "classic-margarita-cost-sheet.pdf".
    public var fileName: String {
        let slug = title.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
        let collapsed = String(slug).split(separator: "-").joined(separator: "-")
        return "\(collapsed.isEmpty ? "drink" : collapsed)-\(fileSuffix).pdf"
    }
}

extension AppStore {
    public func costSheet(for r: Recipe) -> CostSheet {
        let t = totals(r)
        let title = r.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled drink" : r.name
        let currencyName = Catalog.currencies.first { $0.code == settings.currency }?.name ?? settings.currency
        var h = ""

        h += "<h1>\(esc(title))</h1>"
        h += "<p class=\"muted\">Cost analysis · \(esc(displayDate(now()))) · Prices in \(esc(currencyName)) (\(esc(settings.currency)))</p>"

        // Ingredients
        h += "<h2>Ingredients</h2><table><thead><tr><th>Ingredient</th><th>Package</th><th class=\"r\">Price</th><th>Used</th><th class=\"r\">Cost</th><th class=\"r\">Share</th></tr></thead><tbody>"
        for l in r.lines {
            let x = resolve(l)
            let res = t.line(l.id)
            let used = l.amount.isEmpty ? "—" : "\(l.amount) \(unitLabel(l.amountUnit, pour: true))"
            let cost = res?.status == .ok ? money(res?.cost) : (res?.status == .invalid ? "check entry" : "incomplete")
            let share = t.shares[l.id].map { formatPct($0, places: 1) } ?? "—"
            h += "<tr><td>\(esc(x.name.isEmpty ? "Unnamed ingredient" : x.name))</td><td>\(esc(packageLabel(size: x.size, unit: x.sizeUnit)))</td>"
            h += "<td class=\"r\">\(esc(money(typed: x.price)))</td><td>\(esc(used))</td><td class=\"r\">\(esc(cost))</td><td class=\"r\">\(esc(share))</td></tr>"
        }
        h += "<tr class=\"sub\"><td colspan=\"4\">Ingredient cost</td><td class=\"r\">\(esc(money(t.ingredientCost)))</td><td></td></tr>"
        let extras = Catalog.extras.compactMap { e -> (String, Decimal)? in
            guard let v = parseNumber(r.extras[e.key]).value, v > 0 else { return nil }
            return (e.label, v)
        }
        for (label, v) in extras {
            let share = t.drinkCost > 0 ? formatPct(v / t.drinkCost * 100, places: 1) : "—"
            h += "<tr><td colspan=\"4\">\(esc(label)) (additional cost)</td><td class=\"r\">\(esc(money(v)))</td><td class=\"r\">\(esc(share))</td></tr>"
        }
        h += "<tr class=\"tot\"><td colspan=\"4\">Cost per drink</td><td class=\"r\">\(esc(money(t.drinkCost)))</td><td class=\"r\">\(t.hasCost ? "100%" : "—")</td></tr>"
        h += "</tbody></table>"

        if let top = biggestCostDriver(t), let line = r.lines.first(where: { $0.id == top.id }) {
            let name = resolve(line).name.isEmpty ? "Unnamed ingredient" : resolve(line).name
            let share = t.shares[top.id].map { formatPct($0, places: 1) } ?? ""
            h += "<p><b>Biggest cost driver:</b> \(esc(name)), \(esc(money(top.cost))) (\(esc(share)) of the drink cost).</p>"
        }

        // Assumptions
        var notes: [String] = []
        if let w = parseNumber(r.wastePct).value, w > 0 {
            notes.append("Waste and spillage allowance of \(esc(r.wastePct))% applied to every ingredient without its own waste %.")
        } else {
            notes.append("No recipe-wide waste allowance.")
        }
        for l in r.lines where !l.wastePct.isEmpty {
            let name = resolve(l).name.isEmpty ? "Unnamed ingredient" : resolve(l).name
            notes.append("\(esc(name)): own waste of \(esc(l.wastePct))%.")
        }
        if extras.isEmpty { notes.append("No additional per-drink costs listed.") }
        h += "<h2>Assumptions</h2><ul>" + notes.map { "<li>\($0)</li>" }.joined() + "</ul>"

        // Pricing
        let menu = parseNumber(r.menuPrice).value.flatMap { $0 > 0 ? $0 : nil }
        h += "<h2>Pricing</h2><table><tbody>"
        h += row("Target beverage cost", parseNumber(r.targetPct).value.map { "\(plainString($0))%" } ?? "—")
        h += row("Suggested menu price", money(t.suggestedPrice))
        h += row("Menu price", money(menu))
        h += row("Beverage cost", formatPct(t.bevCostPct))
        h += row("Gross profit per drink", money(t.grossProfit))
        h += row("Gross margin", formatPct(t.grossMargin))
        h += "</tbody></table>"

        let ladder = priceLadder(t)
        if !ladder.isEmpty {
            h += "<h2>Price ladder</h2><table><thead><tr><th>Beverage cost</th><th class=\"r\">Menu price</th><th class=\"r\">Gross profit per drink</th></tr></thead><tbody>"
            for step in ladder {
                h += "<tr><td>\(esc(formatPct(step.targetPct, places: 0)))</td><td class=\"r\">\(esc(money(step.price)))</td><td class=\"r\">\(esc(money(step.price - t.drinkCost)))</td></tr>"
            }
            h += "</tbody></table>"
        }

        let batch = batchRows(t)
        if !batch.isEmpty {
            h += "<h2>Batch</h2><table><tbody>" + batch.map { row($0.label, $0.value) }.joined() + "</tbody></table>"
        }

        h += "<p class=\"muted\">Figures cover ingredient and listed additional costs only. They do not include labor, rent, taxes or overhead. Prices are rounded to the cent for display; calculations use exact values.</p>"

        let doc = printPage(title: "\(title) cost analysis", body: h)
        return CostSheet(html: doc, title: title)
    }

    func row(_ label: String, _ value: String) -> String {
        "<tr><td>\(esc(label))</td><td class=\"r\">\(esc(value))</td></tr>"
    }
}

/// Escapes text for HTML.
func esc(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for c in s {
        switch c {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        case "'": out += "&#39;"
        default: out.append(c)
        }
    }
    return out
}
