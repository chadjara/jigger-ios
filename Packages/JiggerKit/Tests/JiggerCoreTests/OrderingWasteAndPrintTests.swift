import XCTest
import JiggerEngine
@testable import JiggerCore

/// Reordering, waste for all ingredients, duplicate protection and the recipe book / price list.
final class OrderingWasteAndPrintTests: XCTestCase {
    private func names(_ s: AppStore) -> [String] { s.draft.lines.map(\.name) }

    // MARK: Reordering

    func testQuickMovesTopUpDownBottom() {
        let s = makeStore()
        XCTAssertEqual(names(s), ["Blanco tequila", "Triple sec", "Fresh lime juice", "Agave syrup", "Lime (garnish wheel)"])
        let garnish = s.lineID(4)
        s.moveLine(garnish, .top)
        XCTAssertEqual(names(s).first, "Lime (garnish wheel)")
        s.moveLine(garnish, .down)
        XCTAssertEqual(names(s)[1], "Lime (garnish wheel)")
        s.moveLine(garnish, .bottom)
        XCTAssertEqual(names(s).last, "Lime (garnish wheel)")
        s.moveLine(garnish, .up)
        XCTAssertEqual(names(s)[3], "Lime (garnish wheel)")
        XCTAssertFalse(s.canMoveLine(s.lineID(0), .up))
        XCTAssertFalse(s.canMoveLine(s.lineID(4), .bottom))
        XCTAssertTrue(s.canMoveLine(s.lineID(2), .top))
        // totals don't depend on order
        XCTAssertEqual(s.drinkCostText, "$3.69")
    }

    func testMovingFirstLineUpOrLastLineDownChangesNothing() {
        let s = makeStore()
        let before = s.draft
        s.moveLine(s.lineID(0), .up)
        s.moveLine(s.lineID(4), .down)
        XCTAssertEqual(s.draft, before)
    }

    func testDragOffsetsFollowSwiftUIOnMoveSemantics() {
        let s = makeStore()
        // drag the last line to the very top
        s.moveLines(fromOffsets: IndexSet(integer: 4), toOffset: 0)
        XCTAssertEqual(names(s).first, "Lime (garnish wheel)")
        // drag the first line to the end (destination = count)
        s.moveLines(fromOffsets: IndexSet(integer: 0), toOffset: 5)
        XCTAssertEqual(names(s).last, "Lime (garnish wheel)")
        // drag the first two below the third
        s.moveLines(fromOffsets: IndexSet([0, 1]), toOffset: 3)
        XCTAssertEqual(names(s), ["Fresh lime juice", "Blanco tequila", "Triple sec", "Agave syrup", "Lime (garnish wheel)"])
        // out-of-range input is ignored
        let before = s.draft
        s.moveLines(fromOffsets: IndexSet(integer: 9), toOffset: 0)
        s.moveLines(fromOffsets: IndexSet(integer: 0), toOffset: 9)
        XCTAssertEqual(s.draft, before)
    }

    func testReorderingMarksASavedRecipeAsChanged() {
        let s = makeStore()
        s.saveRecipe()
        s.moveLine(s.lineID(4), .top)
        XCTAssertEqual(s.saveStatus, .unsavedChanges)
    }

    // MARK: Waste for all ingredients

    func testRecipeWasteAppliesToAllAndOverridesCanBeCleared() {
        let s = makeStore()
        s.setRecipe(.wastePct, "10")
        s.setLine(s.lineID(0), .wastePct, "0")
        s.setLine(s.lineID(1), .wastePct, "5")
        XCTAssertEqual(s.linesWithOwnWaste, 2)
        s.applyRecipeWasteToAll()
        XCTAssertEqual(s.linesWithOwnWaste, 0)
        XCTAssertEqual(s.toast?.message, "10% waste on every ingredient")
        // 3.693… / 0.9 = 4.1035…
        XCTAssertEqual(s.drinkCostText, "$4.10")
        s.undoToast()
        XCTAssertEqual(s.linesWithOwnWaste, 2)
        XCTAssertEqual(s.draft.lines[1].wastePct, "5")
    }

    func testExtrasSummaryNoLongerMentionsWaste() {
        let s = makeStore()
        s.setRecipe(.wastePct, "10")
        XCTAssertEqual(s.extrasSummary(s.draft, s.draftTotals), "None added")
    }

    // MARK: Duplicate ingredients

    func testAddingAnIdenticalIngredientIsRefused() {
        let s = makeStore()
        XCTAssertTrue(s.addLibraryItem(name: "Tito’s Vodka", price: "24.99", size: "750", sizeUnit: .ml))
        XCTAssertFalse(s.addLibraryItem(name: "  tito’s   vodka ", price: "22.00", size: "750.0", sizeUnit: .ml))
        XCTAssertEqual(s.toast?.message, "Already in My Ingredients")
        XCTAssertEqual(s.library.count, 1)
        // a different bottle size is a different ingredient
        XCTAssertTrue(s.addLibraryItem(name: "Tito’s Vodka", price: "39.99", size: "1.75", sizeUnit: .l))
        XCTAssertEqual(s.library.count, 2)
    }

    func testSavingAnIdenticalIngredientFromARecipeLinksInsteadOfDuplicating() {
        let s = makeStore()
        s.addLibraryItem(name: "Blanco tequila", price: "30.00", size: "750", sizeUnit: .ml)
        XCTAssertEqual(s.saveLineToLibrary(s.lineID(0)), .saved) // the example row: Blanco tequila, $32, 750 mL
        XCTAssertEqual(s.library.count, 1)
        XCTAssertEqual(s.draft.lines[0].libId, s.library[0].id)
        XCTAssertTrue(s.draft.lines[0].priceOverride, "the recipe's own $32 price is kept, not silently replaced")
        XCTAssertEqual(s.resolve(s.draft.lines[0]).price, "32.00")
    }

    func testRenamingIntoADuplicateIsFlagged() {
        let s = makeStore()
        s.addLibraryItem(name: "Gin", price: "28", size: "1", sizeUnit: .l)
        s.addLibraryItem(name: "Rum", price: "20", size: "1", sizeUnit: .l)
        let rum = s.library.first { $0.name == "Rum" }!
        s.updateLibraryItem(rum.id, .name, "gin")
        XCTAssertTrue(s.invalidFields(s.libraryItem(rum.id)!).contains(.name))
    }

    // MARK: Printed documents

    func testRecipeBookHasTheSummaryAndASpecPerDrink() {
        let s = makeStore()
        s.saveRecipe()
        s.setRecipe(.wastePct, "5")
        s.duplicateRecipe(s.recipes[0].id)
        let book = s.recipeBook()
        let h = book.html
        XCTAssertEqual(book.fileName, "jigger-recipe-book.pdf")
        for expected in ["Recipe book", "2 drinks", "At a glance", "Specs", "Classic Margarita", "Classic Margarita (copy)",
                         "2 oz", "Blanco tequila", "$2.52", "$3.69", "26.4%", "$18.47 at 20%", "US dollar (USD)",
                         "not labor, rent, taxes or overhead"] {
            XCTAssertTrue(h.contains(expected), "recipe book is missing \(expected)")
        }
        XCTAssertFalse(h.contains("NaN"))
    }

    func testPriceListShowsUnitCostAndUsage() {
        let s = makeStore()
        s.addLibraryItem(name: "Tito’s Vodka", price: "24.99", size: "750", sizeUnit: .ml)
        s.addLibraryItem(name: "Lime", price: "0.50", size: "1", sizeUnit: .each)
        s.addLibraryItem(name: "Sugar", price: "3", size: "2", sizeUnit: .lb)
        let list = s.ingredientPriceList()
        let h = list.html
        XCTAssertEqual(list.fileName, "jigger-price-list.pdf")
        for expected in ["Bar price list", "3 ingredients", "Tito’s Vodka", "750 mL", "$24.99", "$0.99 / oz",
                         "$0.50 / each", "$0.09 / oz wt"] {
            XCTAssertTrue(h.contains(expected), "price list is missing \(expected)")
        }
        // the oz/mL setting switches volume quotes to 10 mL
        s.setDisplayUnit("ml")
        XCTAssertTrue(s.ingredientPriceList().html.contains("$0.33 / 10 mL"))
    }
}
