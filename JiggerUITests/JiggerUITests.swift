import XCTest

/// End-to-end tests through the real UI, covering the flows in reference/ui.test.js.
/// Each test launches a fresh app with its own storage (see "-uitesting" in JiggerApp).
final class JiggerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @discardableResult
    private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + (reset ? ["-reset"] : [])
        app.launch()
        self.app = app
        XCTAssertTrue(element("recipeName").waitForExistence(timeout: 20), "calculator did not appear")
        return app
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func field(_ id: String) -> XCUIElement {
        app.textFields[id].firstMatch
    }

    private func text(_ id: String) -> String {
        let e = app.staticTexts[id].firstMatch
        XCTAssertTrue(e.waitForExistence(timeout: 5), "\(id) not found")
        return e.label
    }

    private func type(_ id: String, _ value: String) {
        let f = field(id)
        XCTAssertTrue(f.waitForExistence(timeout: 5), "\(id) not found")
        f.tap()
        if let current = f.value as? String, !current.isEmpty, current != f.placeholderValue {
            f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        f.typeText(value)
    }

    private func tap(_ id: String) {
        let e = element(id)
        XCTAssertTrue(e.waitForExistence(timeout: 5), "\(id) not found")
        e.tap()
    }

    private func goTo(_ tab: String, sidebarID: String) {
        let tabButton = app.tabBars.buttons[tab].firstMatch
        if tabButton.exists { tabButton.tap() } else { tap(sidebarID) }
    }

    private func dismissKeyboard() {
        let done = app.toolbars.buttons["Done"].firstMatch
        if done.exists { done.tap() }
    }

    // MARK: - Tests

    func testFirstLaunchShowsTheMargaritaExampleWithCorrectTotals() {
        launch()
        XCTAssertEqual(field("recipeName").value as? String, "Classic Margarita")
        XCTAssertTrue(element("exampleNotice").exists)
        XCTAssertEqual(text("row0.cost"), "$2.52")
        XCTAssertEqual(text("drinkCost"), "$3.69")
        XCTAssertEqual(text("suggestedPrice"), "$18.47")
        XCTAssertEqual(text("bevCostPct"), "26.4%")
        XCTAssertEqual(text("grossProfit"), "$10.31")
        XCTAssertEqual(text("grossMargin"), "73.6%")
        XCTAssertTrue(text("comparison").contains("below the suggested price"))
    }

    func testAddFillRemoveAndUndoAnIngredient() {
        launch()
        tap("clearExample")
        type("row0.name", "Vodka")
        type("row0.price", "24.99")
        type("row0.amount", "2")
        dismissKeyboard()
        XCTAssertEqual(text("row0.cost"), "$1.97")
        XCTAssertEqual(text("drinkCost"), "$1.97")
        XCTAssertEqual(text("suggestedPrice"), "$9.85")
        tap("addIngredient")
        XCTAssertTrue(field("row1.name").waitForExistence(timeout: 5))
        dismissKeyboard()
        tap("row0.remove")
        XCTAssertFalse(field("row1.name").exists)
        XCTAssertEqual(text("drinkCost"), "$0.00")
        tap("toastUndo")
        XCTAssertTrue(field("row1.name").waitForExistence(timeout: 5))
        XCTAssertEqual(text("drinkCost"), "$1.97")
    }

    func testOzMLToggleChangesDisplayOnlyAndPourChipsSetTheAmount() {
        launch()
        app.segmentedControls["unitToggle"].buttons["mL"].tap()
        XCTAssertEqual(field("row0.amount").value as? String, "60")
        XCTAssertEqual(field("row3.amount").value as? String, "15")
        XCTAssertEqual(text("drinkCost"), "$3.69")
        XCTAssertTrue(text("row0.enteredAs").contains("Entered as 2 oz"))
        app.segmentedControls["unitToggle"].buttons["oz"].tap()
        XCTAssertEqual(field("row0.amount").value as? String, "2")
        app.segmentedControls["unitToggle"].buttons["mL"].tap()
        tap("row0.pour.30")
        XCTAssertEqual(text("row0.cost"), "$1.28")
    }

    func testInvalidInputShowsAMessageAndNeverNaN() {
        launch()
        tap("clearExample")
        type("row0.price", "abc")
        dismissKeyboard()
        XCTAssertEqual(text("row0.cost"), "—")
        XCTAssertTrue(element("row0.error").exists)
        type("menuPrice", "0")
        dismissKeyboard()
        XCTAssertTrue(element("menuError").exists)
        XCTAssertEqual(text("bevCostPct"), "—")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'NaN'")).firstMatch.exists)
    }

    func testBatchScaling() {
        launch()
        tap("servings.100")
        XCTAssertEqual(text("drinkCost"), "$3.69")
        XCTAssertTrue(text("batch0").contains("$369.32"))
        XCTAssertTrue(text("batch1").contains("$1,400.00"))
    }

    func testSavePersistsAcrossRelaunchAndAppearsInSavedRecipes() {
        launch()
        tap("saveRecipe")
        XCTAssertEqual(text("saveState"), "Saved")
        type("menuPrice", "15")
        dismissKeyboard()
        XCTAssertEqual(text("saveState"), "Unsaved changes")
        tap("saveRecipe")
        app.terminate()
        launch(reset: false)
        XCTAssertEqual(field("recipeName").value as? String, "Classic Margarita")
        XCTAssertEqual(field("menuPrice").value as? String, "15")
        XCTAssertEqual(text("saveState"), "Saved")
        goTo("Recipes", sidebarID: "sidebar.recipes")
        XCTAssertTrue(element("open.Classic Margarita").waitForExistence(timeout: 5))
    }

    func testSaveToLibraryAndTheIngredientLimit() {
        launch()
        tap("row0.saveToLibrary")
        XCTAssertTrue(element("row0.tag").waitForExistence(timeout: 5))
        for _ in 0..<20 { tap("addIngredient"); dismissKeyboard() }
        XCTAssertTrue(element("limitNote").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["addIngredient"].isEnabled)
        goTo("Ingredients", sidebarID: "sidebar.ingredients")
        XCTAssertTrue(field("lib.Blanco tequila.price").waitForExistence(timeout: 5))
        XCTAssertEqual(text("lib.Blanco tequila.used"), "Not in a recipe")
    }

    /// iPad: sidebar navigation with the calculator and summary side by side.
    func testIPadShowsSidebarAndSummaryBesideTheCalculator() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layout only")
        launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(element("sidebar.recipes").waitForExistence(timeout: 5))
        let row = field("row0.price"), cost = app.staticTexts["drinkCost"]
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(cost.isHittable)
        XCTAssertGreaterThan(cost.frame.minX, row.frame.maxX, "summary should sit to the right of the ingredients")
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }
}
