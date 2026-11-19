import XCTest
import JiggerEngine
@testable import JiggerCore

/// Persistence, backups, cost sheet and edge cases beyond the web suite.
final class StoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("jigger-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testJSONFileStoreRoundTripsTheWholeState() throws {
        let file = JSONFileStore(url: tempDir.appendingPathComponent("state.json"))
        let s1 = AppStore(storage: file, locale: Locale(identifier: "en_US"), autosaveDelay: nil)
        s1.setRecipe(.menuPrice, "15")
        s1.saveRecipe()
        s1.addLibraryItem(name: "Gin", price: "28", size: "1", sizeUnit: .l)
        s1.setDisplayUnit("ml")
        s1.flush()
        let s2 = AppStore(storage: JSONFileStore(url: file.url), locale: Locale(identifier: "en_US"), autosaveDelay: nil)
        XCTAssertEqual(s2.state, s1.state)
        XCTAssertEqual(s2.settings.displayUnit, "ml")
    }

    func testUnreadableStateFileIsSetAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("state.json")
        try Data("{ not json".utf8).write(to: url)
        let s = AppStore(storage: JSONFileStore(url: url), autosaveDelay: nil)
        XCTAssertEqual(s.draft.name, "Classic Margarita")
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("state-unreadable-") })
    }

    func testStorageFailureWarnsOnce() {
        let storage = MemoryStore()
        storage.failSaves = true
        let s = makeStore(storage)
        s.flush()
        XCTAssertTrue(s.toast!.message.contains("Couldn’t save"))
        s.toast = nil
        s.flush()
        XCTAssertNil(s.toast)
    }

    func testExportThenImportIntoAFreshStoreRestoresEverything() throws {
        let a = makeStore()
        a.saveRecipe()
        a.addLibraryItem(name: "Gin", price: "28", size: "1", sizeUnit: .l)
        let data = try a.exportBackup()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"app\" : \"jigger\""))
        let b = makeStore()
        let summary = b.importBackup(data)
        XCTAssertEqual(summary, ImportSummary(recipes: 1, ingredients: 1))
        XCTAssertEqual(b.recipes, a.recipes)
        XCTAssertEqual(b.library, a.library)
        // importing again replaces by id instead of duplicating
        b.importBackup(data)
        XCTAssertEqual(b.recipes.count, 1)
        XCTAssertTrue(a.backupFileName.hasPrefix("jigger-backup-"))
    }

    func testImportIsLenientAboutNumbersNullsUnknownUnitsAndJunkEntries() {
        let s = makeStore()
        let json = #"{"library":[{"id":"g","name":"Gin","price":28,"size":1,"sizeUnit":"barrel"},null,{"name":"no id"}],"recipes":[{"id":"r","name":"X","menuPrice":12.5,"lines":[{"amount":2,"amountUnit":"pinch","libId":null}]},{"lines":"nope"}]}"#
        let summary = s.importBackup(Data(json.utf8))
        XCTAssertEqual(summary, ImportSummary(recipes: 1, ingredients: 1))
        XCTAssertEqual(s.library[0].price, "28")
        XCTAssertEqual(s.library[0].sizeUnit, "ml")
        let r = s.recipes.first { $0.id == "r" }!
        XCTAssertEqual(r.menuPrice, "12.5")
        XCTAssertEqual(r.lines[0].amount, "2")
        XCTAssertEqual(r.lines[0].amountUnit, "floz")
        XCTAssertFalse(r.lines[0].id.isEmpty)
        XCTAssertEqual(Set(r.extras.keys), Set(Catalog.extras.map(\.key)))
        XCTAssertNil(s.importBackup(Data(#"{"recipes":[]}"#.utf8))) // library missing
    }

    func testImportCapsLinesAt25() {
        let s = makeStore()
        let lines = (0..<40).map { #"{"id":"l\#($0)","amount":"1"}"# }.joined(separator: ",")
        s.importBackup(Data(#"{"library":[],"recipes":[{"id":"big","name":"Big","lines":[\#(lines)]}]}"#.utf8))
        XCTAssertEqual(s.recipes[0].lines.count, 25)
    }

    func testNewRecipeSetsAsideUnsavedChangesWithUndo() {
        let s = makeStore()
        s.setRecipe(.name, "My drink")
        s.startNewRecipe()
        XCTAssertEqual(s.draft.name, "")
        XCTAssertEqual(s.draft.lines.count, 1)
        XCTAssertTrue(s.toast!.message.contains("Unsaved changes to My drink were set aside"))
        s.undoToast()
        XCTAssertEqual(s.draft.name, "My drink")
        // a clean draft is replaced without an undo
        s.saveRecipe()
        s.startNewRecipe()
        XCTAssertEqual(s.toast?.message, "Started a new recipe")
        XCTAssertNil(s.toast?.undo)
    }

    func testSaveNamesUntitledDrinksAndClearsTheExampleFlag() {
        let s = makeStore()
        s.clearExample()
        XCTAssertEqual(s.saveStatus, .empty)
        s.setLine(s.lineID(0), .price, "10")
        XCTAssertEqual(s.saveStatus, .notSavedYet)
        s.saveRecipe()
        XCTAssertEqual(s.recipes[0].name, "Untitled drink")
        XCTAssertFalse(s.recipes[0].isExample)
    }

    func testSaveToLibraryValidatesFirst() {
        let s = makeStore()
        s.clearExample()
        let id = s.lineID(0)
        XCTAssertEqual(s.saveLineToLibrary(id), .needsName)
        s.setLine(id, .name, "Rum")
        XCTAssertEqual(s.saveLineToLibrary(id), .needsPrice)
        s.setLine(id, .price, "20")
        s.useCustomPackage(id)
        s.setLine(id, .size, "0")
        XCTAssertEqual(s.saveLineToLibrary(id), .needsSize)
        s.setLine(id, .size, "1")
        XCTAssertEqual(s.saveLineToLibrary(id), .saved)
        XCTAssertFalse(s.addLibraryItem(name: " ", price: "1", size: "1", sizeUnit: .ml))
        XCTAssertFalse(s.addLibraryItem(name: "A", price: "-1", size: "1", sizeUnit: .ml))
        XCTAssertFalse(s.addLibraryItem(name: "A", price: "1", size: "0", sizeUnit: .ml))
    }

    func testChangingALibraryUnitToWeightFixesLinkedLines() {
        let s = makeStore()
        s.clearExample()
        s.addLibraryItem(name: "Sugar", price: "3", size: "2", sizeUnit: .ml)
        let id = s.addLine(fromLibrary: s.library[0].id)!
        XCTAssertEqual(s.draft.lines.first { $0.id == id }?.amountUnit, "floz")
        s.setLibrarySizeUnit(s.library[0].id, .lb)
        XCTAssertEqual(s.draft.lines.first { $0.id == id }?.amountUnit, "ozwt")
        XCTAssertTrue(s.invalidFields(LibraryItem(id: "z", name: "", price: "x", size: "0", sizeUnit: "ml")) == [.name, .price, .size])
    }

    func testPresetPackagesAndDefaultTarget() {
        let s = makeStore()
        s.clearExample()
        let id = s.lineID(0)
        s.choosePreset(id, Catalog.packagePresets.last!) // 1.75 L
        XCTAssertEqual(s.draft.lines[0].size, "1.75")
        s.useCustomPackage(id)
        s.setLine(id, .size, "2")
        s.setSizeUnit(id, .kg)
        XCTAssertEqual(s.draft.lines[0].amountUnit, "g")
        s.usePresetPackages(id)
        XCTAssertEqual(s.draft.lines[0].size, "750")
        XCTAssertEqual(s.draft.lines[0].sizeUnit, "ml")
        XCTAssertEqual(s.draft.lines[0].amountUnit, "floz")
        XCTAssertFalse(s.setDefaultTarget("0"))
        XCTAssertFalse(s.setDefaultTarget("abc"))
        XCTAssertTrue(s.setDefaultTarget(" 22 "))
        s.startNewRecipe()
        XCTAssertEqual(s.draft.targetPct, "22")
    }

    func testResetDeletesRecipesAndIngredientsButKeepsSettings() {
        let s = makeStore()
        s.saveRecipe()
        s.addLibraryItem(name: "Gin", price: "28", size: "1", sizeUnit: .l)
        s.setCurrency("GBP")
        s.resetAll()
        XCTAssertTrue(s.recipes.isEmpty)
        XCTAssertTrue(s.library.isEmpty)
        XCTAssertEqual(s.settings.currency, "GBP")
        XCTAssertFalse(s.draft.isExample)
    }

    func testDecimalCommaInputIsNormalisedOnlyInCommaLocales() {
        XCTAssertEqual(normalizeDecimalInput("24,99", decimalSeparator: ","), "24.99")
        XCTAssertEqual(normalizeDecimalInput("1,000", decimalSeparator: "."), "1,000")
    }

    func testCostSheetHasEveryRequiredSection() {
        let s = makeStore()
        s.setRecipe(.servings, "25")
        s.setRecipe(.wastePct, "5")
        s.setExtra("napkins", "0.02")
        let sheet = s.costSheet(for: s.draft)
        let h = sheet.html
        XCTAssertEqual(sheet.fileName, "classic-margarita-cost-sheet.pdf")
        for expected in ["Classic Margarita", "Blanco tequila", "Share", "Biggest cost driver:</b> Blanco tequila",
                         "Napkin (additional cost)", "allowance of 5%", "Target beverage cost", "Suggested menu price",
                         "Menu price", "Beverage cost", "Gross profit per drink", "Gross margin", "Price ladder",
                         "18%", "20%", "22%", "25%", "Ingredient cost for 25 drinks", "US dollar (USD)",
                         "do not include labor, rent, taxes or overhead"] {
            XCTAssertTrue(h.contains(expected), "cost sheet is missing \(expected)")
        }
        XCTAssertFalse(h.contains("NaN"))
        // names are escaped
        s.setRecipe(.name, "<b>Tom & Jerry</b>")
        XCTAssertTrue(s.costSheet(for: s.draft).html.contains("&lt;b&gt;Tom &amp; Jerry&lt;/b&gt;"))
    }
}
