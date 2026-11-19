import XCTest
import JiggerEngine
@testable import JiggerCore

/// The scenarios of reference/ui.test.js, run against the app's store (same inputs, same expected figures).
/// The XCUITest suite drives the same flows through the real UI.
final class AppBehaviorTests: XCTestCase {
    func testFirstVisitShowsTheMargaritaExampleWithCorrectTotals() {
        let s = makeStore()
        XCTAssertEqual(s.draft.name, "Classic Margarita")
        XCTAssertTrue(s.draft.isExample)
        XCTAssertEqual(s.draft.lines.count, 5)
        // tequila 2oz of $32/750 = 2.5236 ; triple 0.5518 ; lime 0.2662 ; agave 0.2514 ; garnish 0.10 => 3.693
        XCTAssertEqual(s.costText(0), "$2.52")
        XCTAssertEqual(s.drinkCostText, "$3.69")
        XCTAssertEqual(s.suggestedText, "$18.47")
        let t = s.draftTotals
        XCTAssertEqual(formatPct(t.bevCostPct), "26.4%")
        XCTAssertEqual(s.money(t.grossProfit), "$10.31")
        XCTAssertEqual(formatPct(t.grossMargin), "73.6%")
        XCTAssertTrue(s.comparisonText(s.draft, t)!.contains("below the suggested price"))
    }

    func testAddFillRemoveAndUndoAnIngredient() {
        let s = makeStore()
        s.clearExample()
        XCTAssertEqual(s.draft.lines.count, 1)
        let id = s.lineID(0)
        s.setLine(id, .name, "Tito’s Vodka")
        s.setLine(id, .price, "24.99")
        s.setLine(id, .amount, "2")
        XCTAssertEqual(s.costText(0), "$1.97")
        XCTAssertEqual(s.drinkCostText, "$1.97")
        XCTAssertEqual(s.suggestedText, "$9.85")
        XCTAssertNotNil(s.addLine())
        XCTAssertEqual(s.draft.lines.count, 2)
        s.removeLine(id)
        XCTAssertEqual(s.draft.lines.count, 1)
        XCTAssertEqual(s.drinkCostText, "$0.00")
        XCTAssertEqual(s.toast?.message, "Removed Tito’s Vodka")
        s.undoToast()
        XCTAssertEqual(s.draft.lines.count, 2)
        XCTAssertEqual(s.draft.lines[0].id, id)
        XCTAssertEqual(s.drinkCostText, "$1.97")
    }

    func testOzMLToggleChangesDisplayOnlyCostAndSourceStayPut() {
        let s = makeStore()
        let before = s.drinkCostText
        s.setDisplayUnit("ml")
        XCTAssertEqual(s.displayAmount(s.draft.lines[0]), "60")
        XCTAssertEqual(s.displayAmount(s.draft.lines[3]), "15")
        XCTAssertEqual(s.drinkCostText, before)
        XCTAssertTrue(s.enteredAsNote(s.draft.lines[0])!.contains("Entered as 2 oz"))
        for _ in 0..<10 { s.setDisplayUnit("floz"); s.setDisplayUnit("ml") }
        XCTAssertEqual(s.draft.lines[0].amount, "2")
        XCTAssertEqual(s.draft.lines[0].amountUnit, "floz")
        // typing in mL makes mL the source
        s.setLine(s.lineID(0), .amount, "45")
        XCTAssertEqual(s.draft.lines[0].amountUnit, "ml")
        XCTAssertEqual(s.costText(0), "$1.92") // 45/750*32
        // pour chips
        s.tapPour(s.lineID(0), "30")
        XCTAssertEqual(s.costText(0), "$1.28")
        XCTAssertTrue(s.isPourSelected(s.draft.lines[0], "30"))
        XCTAssertFalse(s.isPourSelected(s.draft.lines[0], "45"))
    }

    func testCountAndWeightIngredients() {
        let s = makeStore()
        s.clearExample()
        let lime = s.lineID(0)
        s.setLine(lime, .name, "Lime")
        s.useCustomPackage(lime)
        s.setLine(lime, .size, "1")
        s.setSizeUnit(lime, .each)
        s.setLine(lime, .price, "0.50")
        s.setLine(lime, .amount, "1/2")
        XCTAssertEqual(s.draft.lines[0].amountUnit, "each")
        XCTAssertEqual(s.costText(0), "$0.25")
        // weight: sugar 2 lb bag $3, 10 g
        let sugar = s.addLine()!
        s.useCustomPackage(sugar)
        s.setLine(sugar, .size, "2")
        s.setSizeUnit(sugar, .lb)
        XCTAssertEqual(s.draft.lines[1].amountUnit, "ozwt")
        s.setAmountUnit(sugar, .g)
        s.setLine(sugar, .price, "3")
        s.setLine(sugar, .amount, "10")
        XCTAssertEqual(s.costText(1), "$0.03")
        XCTAssertNotEqual(dimension(of: s.draft.lines[1].sizeUnit), .volume) // no fluid pour chips for weight
        XCTAssertNil(s.enteredAsNote(s.draft.lines[1]))
    }

    func testInvalidInputsShowMessagesAndAreExcludedNeverNaN() {
        let s = makeStore()
        let id = s.lineID(0)
        s.setLine(id, .price, "abc")
        XCTAssertEqual(s.costText(0), "—")
        XCTAssertFalse(s.draftTotals.line(id)!.errorMessages.isEmpty)
        s.setRecipe(.targetPct, "0")
        XCTAssertNotNil(s.draftTotals.targetError)
        XCTAssertEqual(s.suggestedText, "—")
        s.setRecipe(.menuPrice, "0")
        XCTAssertEqual(formatPct(s.draftTotals.bevCostPct), "—")
        s.setLine(id, .wastePct, "100")
        XCTAssertTrue(s.draftTotals.line(id)!.errorMessages.joined().contains("Waste"))
        let t = s.draftTotals
        let texts = [s.drinkCostText, s.suggestedText, formatPct(t.bevCostPct), s.money(t.grossProfit), formatPct(t.grossMargin)]
            + s.draft.lines.indices.map { s.costText($0) } + s.batchRows(t).map(\.value)
        XCTAssertFalse(texts.joined().contains("NaN"))
    }

    func testWasteAndAdditionalCosts() {
        let s = makeStore()
        s.clearExample()
        let id = s.lineID(0)
        s.setLine(id, .price, "27"); s.setLine(id, .amount, "1") // 750 mL bottle
        s.setDisplayUnit("ml")
        s.setLine(id, .amount, "25") // 25/750*27 = 0.90
        XCTAssertEqual(s.drinkCostText, "$0.90")
        s.setRecipe(.wastePct, "10")
        XCTAssertEqual(s.drinkCostText, "$1.00")
        s.setLine(id, .wastePct, "0") // row override
        XCTAssertEqual(s.drinkCostText, "$0.90")
        s.setExtra("napkins", "0.05")
        s.setExtra("straws", "0.05")
        XCTAssertEqual(s.drinkCostText, "$1.00")
        XCTAssertTrue(s.extrasSummary(s.draft, s.draftTotals).contains("$0.10"))
        s.setRecipe(.wastePct, "abc")
        XCTAssertNotNil(s.recipeWasteError(s.draft))
    }

    func testScalingShowsBatchTotalsSeparatelyFromPerDrink() {
        let s = makeStore()
        XCTAssertTrue(s.batchRows(s.draftTotals).isEmpty)
        s.setRecipe(.servings, "100")
        XCTAssertEqual(s.drinkCostText, "$3.69")
        let rows = s.batchRows(s.draftTotals)
        XCTAssertEqual(rows[0], DisplayRow(label: "Ingredient cost for 100 drinks", value: "$369.32"))
        XCTAssertEqual(rows[1], DisplayRow(label: "Revenue for 100 drinks", value: "$1,400.00"))
        XCTAssertEqual(rows[2].tone, .good)
    }

    func testSavePersistAcrossRelaunchDuplicateDeleteWithUndoSearch() {
        let storage = MemoryStore()
        var s = makeStore(storage)
        s.saveRecipe()
        XCTAssertEqual(s.saveStatus, .saved)
        s.setRecipe(.menuPrice, "15")
        XCTAssertEqual(s.saveStatus, .unsavedChanges)
        s.saveRecipe()
        s.flush()
        s = makeStore(storage) // relaunch
        XCTAssertEqual(s.draft.name, "Classic Margarita")
        XCTAssertEqual(s.draft.menuPrice, "15")
        XCTAssertEqual(s.saveStatus, .saved)
        XCTAssertEqual(s.recipes.count, 1)
        XCTAssertEqual(s.money(s.totals(s.recipes[0]).drinkCost), "$3.69")
        s.duplicateRecipe(s.recipes[0].id)
        XCTAssertEqual(s.recipes.count, 2)
        XCTAssertEqual(s.filteredRecipes("copy").count, 1)
        s.deleteRecipe(s.filteredRecipes("copy")[0].id)
        XCTAssertEqual(s.filteredRecipes("copy").count, 0)
        s.undoToast()
        XCTAssertEqual(s.filteredRecipes("").count, 2)
        // open the copy
        s.openRecipe(s.filteredRecipes("copy")[0].id)
        XCTAssertEqual(s.draft.name, "Classic Margarita (copy)")
        // searching by ingredient name works too
        XCTAssertEqual(s.filteredRecipes("tequila").count, 2)
    }

    func testIngredientLibraryFlowPricesFlowThroughOverridesRespected() {
        let s = makeStore()
        s.clearExample()
        let first = s.lineID(0)
        s.setLine(first, .name, "Tito’s Vodka"); s.setLine(first, .price, "24.99")
        XCTAssertEqual(s.saveLineToLibrary(first), .saved)
        XCTAssertEqual(s.library.count, 1)
        XCTAssertNotNil(s.libraryItem(s.draft.lines[0].libId)) // "From My Ingredients"
        s.setLine(first, .amount, "2")
        s.setRecipe(.name, "Vodka soda")
        s.saveRecipe()
        // add the same bottle to a second line via the picker
        let second = s.addLine(fromLibrary: s.library[0].id)!
        XCTAssertEqual(s.draft.lines.count, 2)
        s.setLine(second, .amount, "1")
        s.setLine(second, .price, "30") // recipe-specific override on line 2
        XCTAssertTrue(s.draft.lines[1].priceOverride) // "Custom price"
        s.saveRecipe()
        // change library price
        XCTAssertEqual(s.usageCount(s.library[0].id), 1)
        s.updateLibraryItem(s.library[0].id, .price, "30")
        XCTAssertEqual(s.resolve(s.draft.lines[0]).price, "30")
        XCTAssertEqual(s.costText(0), "$2.37") // 2oz of $30/750
        XCTAssertEqual(s.draft.lines[1].price, "30") // override kept
        s.setLine(second, .price, "40")
        s.updateLibraryItem(s.library[0].id, .price, "20")
        XCTAssertEqual(s.resolve(s.draft.lines[1]).price, "40") // not silently overwritten
        s.revertPrice(second)
        XCTAssertEqual(s.resolve(s.draft.lines[1]).price, "20")
        // saved version has line1 linked ($20 -> 2oz = 1.58) + line2 override $30 1oz = 1.18
        XCTAssertEqual(s.money(s.totals(s.recipes[0]).drinkCost), "$2.76")
        // delete library item: recipes keep last values
        s.deleteLibraryItem(s.library[0].id)
        XCTAssertEqual(s.library.count, 0)
        XCTAssertEqual(s.recipes[0].lines[0].price, "20")
        XCTAssertNil(s.recipes[0].lines[0].libId)
        XCTAssertEqual(s.money(s.totals(s.recipes[0]).drinkCost), "$2.76")
        s.undoToast()
        XCTAssertEqual(s.library.count, 1)
        XCTAssertNotNil(s.recipes[0].lines[0].libId)
    }

    func testAddLibraryItemDirectlyAnd25IngredientLimit() {
        let s = makeStore()
        XCTAssertTrue(s.addLibraryItem(name: "Campari", price: "29.99", size: "750", sizeUnit: .ml))
        XCTAssertEqual(s.library.count, 1)
        for _ in 0..<30 { s.addLine() }
        XCTAssertEqual(s.draft.lines.count, 25)
        XCTAssertFalse(s.canAddLine)
        XCTAssertNil(s.addLine(fromLibrary: s.library[0].id))
    }

    func testExportImportRoundTripAndSettings() throws {
        let s = makeStore()
        s.saveRecipe()
        let json = #"{"app":"jigger","version":1,"library":[{"id":"x1","name":"Gin","price":"28","size":"1","sizeUnit":"l"}],"recipes":[{"id":"r9","name":"Gimlet","lines":[{"id":"a","libId":"x1","amount":"2","amountUnit":"floz"}],"menuPrice":"13"}]}"#
        XCTAssertNotNil(s.importBackup(Data(json.utf8)))
        XCTAssertEqual(s.recipes.count, 2)
        XCTAssertTrue(s.toast!.message.contains("Imported 1 recipe and 1 ingredient"))
        let gimlet = s.filteredRecipes("gimlet")[0]
        XCTAssertEqual(gimlet.lines.count, 1)
        XCTAssertEqual(s.money(s.totals(gimlet).drinkCost), "$1.66") // 2oz (59.147mL) of $28/L
        // bad import
        XCTAssertNil(s.importBackup(Data("nope".utf8)))
        XCTAssertTrue(s.toast!.message.contains("isn’t a Jigger backup"))
        // currency
        s.setCurrency("EUR")
        s.openRecipe(s.recipes[0].id)
        XCTAssertEqual(s.drinkCostText, "€3.69")
        s.setTheme(.light)
        XCTAssertEqual(s.settings.theme, .light)
    }
}
