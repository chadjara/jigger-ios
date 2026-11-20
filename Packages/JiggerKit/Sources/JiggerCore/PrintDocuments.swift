import Foundation
import JiggerEngine

/// Styles shared by every printed document, so the cost sheet, recipe book and price list match.
/// No letter-spacing: wide tracking splits words into single letters in a PDF's text layer,
/// which breaks search and copy. Capitals alone carry the headings.
let printCSS = """
body{font:10.5pt/1.5 Futura,"Futura-Medium","Trebuchet MS",Helvetica,sans-serif;color:#1E1C1A;margin:0}
h1{font:700 24pt/1.1 Futura,"Futura-Bold",Helvetica,sans-serif;margin:0 0 2pt}
h2{font:700 9pt/1.2 Futura,"Futura-Bold",Helvetica,sans-serif;margin:20pt 0 6pt;color:#6E5320;
   text-transform:uppercase;border-bottom:.75pt solid #8A6A2B;padding-bottom:3pt}
h3{font:700 12pt/1.25 Futura,"Futura-Bold",Helvetica,sans-serif;margin:0 0 3pt}
h3 .aside{float:right;font-weight:500;font-size:10pt;color:#6E5320}
table{width:100%;border-collapse:collapse;margin:4pt 0}
th,td{text-align:left;padding:4pt 6pt;border-bottom:.5pt solid #C4BEB3;vertical-align:top}
th{font-size:7.5pt;text-transform:uppercase;color:#6B655C;font-weight:500}
.r{text-align:right;white-space:nowrap}
.sub td{color:#6B655C}
.tot td{font-weight:700;border-top:1pt solid #1E1C1A;border-bottom:none}
.muted{color:#6B655C;font-size:8.5pt}
ul{margin:4pt 0;padding-left:14pt}
.block{page-break-inside:avoid;padding:10pt 0 8pt;border-bottom:.75pt solid #C4BEB3}
.spec td{border-bottom:.5pt dotted #C4BEB3;padding:2pt 4pt}
.spec .amt{width:16%;white-space:nowrap;color:#6E5320;font-weight:700}
.meta{font-size:9pt;color:#4A4640;margin:4pt 0 0}
"""

extension AppStore {
    /// Wraps a document body in the shared print page.
    func printPage(title: String, body: String) -> String {
        """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><title>\(esc(title))</title>
        <style>\(printCSS)</style></head><body>\(body)</body></html>
        """
    }

    private var currencyLine: String {
        let name = Catalog.currencies.first { $0.code == settings.currency }?.name ?? settings.currency
        return "Prices in \(name) (\(settings.currency))"
    }

    private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    /// Every saved recipe in one condensed document: an at-a-glance table, then a compact spec per drink.
    public func recipeBook() -> CostSheet {
        let recipes = state.recipes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var h = "<h1>Recipe book</h1>"
        h += "<p class=\"muted\">\(plural(recipes.count, "drink")) · \(esc(displayDate(now()))) · \(esc(currencyLine))</p>"

        h += "<h2>At a glance</h2><table><thead><tr><th>Drink</th><th class=\"r\">Cost</th><th class=\"r\">Menu</th>"
        h += "<th class=\"r\">Bev cost</th><th class=\"r\">Profit</th><th class=\"r\">Suggested</th></tr></thead><tbody>"
        for r in recipes {
            let t = totals(r)
            let target = parseNumber(r.targetPct).value.map { " at \(plainString($0))%" } ?? ""
            h += "<tr><td>\(esc(displayName(r)))</td><td class=\"r\">\(esc(money(t.drinkCost)))</td>"
            h += "<td class=\"r\">\(esc(money(typed: r.menuPrice)))</td><td class=\"r\">\(esc(formatPct(t.bevCostPct)))</td>"
            h += "<td class=\"r\">\(esc(money(t.grossProfit)))</td>"
            h += "<td class=\"r\">\(esc(money(t.suggestedPrice)))\(t.suggestedPrice == nil ? "" : esc(target))</td></tr>"
        }
        h += "</tbody></table>"

        h += "<h2>Specs</h2>"
        for r in recipes {
            let t = totals(r)
            let menu = parseNumber(r.menuPrice).value.flatMap { $0 > 0 ? $0 : nil }
            h += "<div class=\"block\"><h3>\(esc(displayName(r)))"
            if let menu { h += "<span class=\"aside\">\(esc(money(menu)))</span>" }
            h += "</h3><table class=\"spec\"><tbody>"
            for l in r.lines {
                let x = resolve(l)
                let res = t.line(l.id)
                let amount = l.amount.isEmpty ? "—" : "\(l.amount) \(unitLabel(l.amountUnit, pour: true))"
                let cost = res?.status == .ok ? money(res?.cost) : "—"
                h += "<tr><td class=\"amt\">\(esc(amount))</td><td>\(esc(x.name.isEmpty ? "Unnamed ingredient" : x.name))</td>"
                h += "<td class=\"r\">\(esc(cost))</td></tr>"
            }
            h += "</tbody></table>"
            let extras = Catalog.extras.compactMap { e -> String? in
                guard let v = parseNumber(r.extras[e.key]).value, v > 0 else { return nil }
                return "\(e.label) \(money(v))"
            }
            var notes: [String] = []
            if !extras.isEmpty { notes.append("Extras: " + extras.joined(separator: ", ")) }
            if let w = parseNumber(r.wastePct).value, w > 0 { notes.append("Waste \(plainString(w))%") }
            if !notes.isEmpty { h += "<p class=\"meta\">\(esc(notes.joined(separator: " · ")))</p>" }
            var figures = ["Cost \(money(t.drinkCost))"]
            if t.bevCostPct != nil { figures.append("Bev cost \(formatPct(t.bevCostPct))") }
            if t.grossProfit != nil { figures.append("Profit \(money(t.grossProfit))") }
            if let s = t.suggestedPrice, let target = parseNumber(r.targetPct).value {
                figures.append("Suggested \(money(s)) at \(plainString(target))%")
            }
            h += "<p class=\"meta\"><b>\(esc(figures.joined(separator: " · ")))</b></p></div>"
        }
        if recipes.isEmpty { h += "<p class=\"muted\">No saved recipes yet.</p>" }
        h += "<p class=\"muted\">Costs cover ingredients and listed additional costs only, not labor, rent, taxes or overhead. Prices are rounded to the cent for display; calculations use exact values.</p>"
        return CostSheet(html: printPage(title: "Recipe book", body: h), title: "Jigger", fileSuffix: "recipe-book")
    }

    /// Every saved ingredient with its price and cost per pour unit, A–Z.
    public func ingredientPriceList() -> CostSheet {
        let items = state.library.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var h = "<h1>Bar price list</h1>"
        h += "<p class=\"muted\">\(plural(items.count, "ingredient")) · \(esc(displayDate(now()))) · \(esc(currencyLine))</p>"
        h += "<table><thead><tr><th>Ingredient</th><th>Package</th><th class=\"r\">Price paid</th><th class=\"r\">Unit cost</th>"
        h += "<th class=\"r\">In recipes</th></tr></thead><tbody>"
        for it in items {
            let uc = unitCost(price: it.price, size: it.size, sizeUnit: it.sizeUnit, volumeDisplayUnit: settings.displayUnit)
            let unit = uc.map { "\(money($0.amount)) / \($0.basis.label)" } ?? "—"
            let used = usageCount(it.id)
            h += "<tr><td>\(esc(it.name))</td><td>\(esc(packageLabel(size: it.size, unit: it.sizeUnit)))</td>"
            h += "<td class=\"r\">\(esc(money(typed: it.price)))</td><td class=\"r\">\(esc(unit))</td>"
            h += "<td class=\"r\">\(used == 0 ? "—" : String(used))</td></tr>"
        }
        h += "</tbody></table>"
        if items.isEmpty { h += "<p class=\"muted\">No saved ingredients yet.</p>" }
        h += "<p class=\"muted\">Unit cost is the price paid divided by the package size, per fluid ounce (or per 10 mL), per ounce by weight, or each. It excludes waste.</p>"
        return CostSheet(html: printPage(title: "Bar price list", body: h), title: "Jigger", fileSuffix: "price-list")
    }

    private func displayName(_ r: Recipe) -> String {
        r.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled drink" : r.name
    }
}
