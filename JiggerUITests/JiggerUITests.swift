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
    private func launch(reset: Bool = true, seed: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + (reset ? ["-reset"] : [])
        // Optional backup to preload (UI tests only; see JiggerApp).
        if let seed { app.launchEnvironment["JIGGER_SEED"] = seed }
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

    /// Types into a field. Any keyboard still up from the previous field is dismissed first,
    /// because it (or its Done bar) can sit on top of the next field and swallow the tap.
    private func type(_ id: String, _ value: String) {
        dismissKeyboard()
        let f = field(id)
        XCTAssertTrue(f.waitForExistence(timeout: 5), "\(id) not found")
        f.tap()
        if let current = f.value as? String, !current.isEmpty, current != f.placeholderValue {
            f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        f.typeText(value)
    }

    private func tap(_ id: String) {
        dismissKeyboard()
        // Wait out any message at the bottom (as a person would) unless we're tapping its Undo.
        if id != "toastUndo" { waitForToastToClear() }
        let e = element(id)
        XCTAssertTrue(e.waitForExistence(timeout: 5), "\(id) not found")
        e.tap()
    }

    private func goTo(_ tab: String, sidebarID: String) {
        let tabButton = app.tabBars.buttons[tab].firstMatch
        if tabButton.exists { tabButton.tap() } else { tap(sidebarID) }
    }

    private func waitForToastToClear() {
        let toast = app.descendants(matching: .any)["toast"].firstMatch
        if toast.exists { _ = toast.waitForNonExistence(timeout: 10) }
    }

    /// Closes the on-screen keyboard if it's up (or about to appear after a programmatic focus change).
    private func dismissKeyboard() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 0.5) else { return }
        let done = app.buttons["keyboardDone"].firstMatch
        if done.exists && done.isHittable { done.tap() } else if app.toolbars.buttons["Done"].firstMatch.exists {
            app.toolbars.buttons["Done"].firstMatch.tap()
        }
        _ = keyboard.waitForNonExistence(timeout: 3)
    }

    /// Opens ingredient row `index` in the editor sheet.
    private func openRow(_ index: Int) {
        tap("row\(index)")
        XCTAssertTrue(field("editor.amount").waitForExistence(timeout: 5), "ingredient editor didn't open")
    }

    /// Forms only load the rows on screen, so scroll the open sheet until the element is there.
    private func reveal(_ id: String) {
        let target = element(id)
        var tries = 0
        while !(target.exists && target.isHittable) && tries < 6 {
            app.swipeUp()
            tries += 1
        }
    }

    private func closeEditor() {
        dismissKeyboard()
        tap("editor.done")
        _ = app.buttons["editor.done"].waitForNonExistence(timeout: 5)
    }

    private var keyboardHasLetters: Bool {
        let kb = app.keyboards.firstMatch
        return kb.keys["q"].exists || kb.buttons["q"].exists || kb.keys["Q"].exists
    }

    // MARK: - Tests

    func testFirstLaunchShowsTheMargaritaExampleWithCorrectTotals() {
        launch()
        XCTAssertEqual(field("recipeName").value as? String, "Classic Margarita")
        XCTAssertTrue(element("exampleNotice").exists, "example notice missing")
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
        openRow(0)
        type("editor.name", "Vodka")
        type("editor.price", "24.99")
        type("editor.amount", "2")
        dismissKeyboard()
        XCTAssertEqual(text("editor.cost"), "$1.97")
        closeEditor()
        XCTAssertEqual(text("row0.cost"), "$1.97")
        XCTAssertEqual(text("drinkCost"), "$1.97")
        XCTAssertEqual(text("suggestedPrice"), "$9.85")
        tap("addIngredient")
        XCTAssertTrue(field("editor.name").waitForExistence(timeout: 5), "new ingredient didn't open in the editor")
        closeEditor()
        XCTAssertTrue(element("row1").waitForExistence(timeout: 5), "new row didn't appear")
        openRow(0)
        reveal("editor.remove")
        tap("editor.remove")
        // The only costed line is gone; Undo straight away while its notice is up.
        XCTAssertEqual(text("drinkCost"), "$0.00")
        tap("toastUndo")
        XCTAssertTrue(element("row1").waitForExistence(timeout: 5), "undo didn't restore the row")
        XCTAssertEqual(text("drinkCost"), "$1.97")
    }

    func testOzMLToggleChangesDisplayOnlyAndPourChipsSetTheAmount() {
        launch()
        app.segmentedControls["unitToggle"].buttons["mL"].tap()
        XCTAssertTrue(text("row0.detail").hasPrefix("60 mL"), "row 1 should show 60 mL")
        XCTAssertEqual(text("drinkCost"), "$3.69")
        openRow(0)
        XCTAssertEqual(field("editor.amount").value as? String, "60")
        XCTAssertTrue(text("editor.enteredAs").contains("Entered as 2 oz"))
        tap("editor.pour.30")
        XCTAssertEqual(text("editor.cost"), "$1.28")
        closeEditor()
        app.segmentedControls["unitToggle"].buttons["oz"].tap()
        XCTAssertTrue(text("row3.detail").hasPrefix("0.5 oz"), "row 4 should be back in oz")
    }

    func testPourStepperMovesByAQuarterOunce() {
        launch()
        openRow(0)
        let stepper = app.steppers["editor.stepper"].firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        let increment = stepper.buttons["Increment"].exists ? stepper.buttons["Increment"] : stepper.buttons.element(boundBy: 1)
        increment.tap()
        XCTAssertEqual(field("editor.amount").value as? String, "2.25")
        closeEditor()
    }

    func testNumberFieldsUseANumberKeyboard() {
        launch()
        openRow(0)
        field("editor.amount").tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(keyboardHasLetters, "the pour field should show a number pad, not letters")
        XCTAssertTrue(app.buttons["fraction.½"].exists, "fraction keys should sit above the number pad")
        dismissKeyboard()
        field("editor.price").tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(keyboardHasLetters, "the price field should show a number pad")
        dismissKeyboard()
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Done should close the keyboard")
        closeEditor()
    }

    func testKeyboardCanBeClosedOnMix() {
        launch()
        assertKeyboardCloses(field: "menuPrice", screen: "Mix")
    }

    func testKeyboardCanBeClosedOnSettings() {
        launch()
        goTo("Settings", sidebarID: "sidebar.settings")
        assertKeyboardCloses(field: "setTarget", screen: "Settings")
    }

    /// Opens the keyboard from `field` and closes it with the Done button above the keyboard.
    private func assertKeyboardCloses(field fieldID: String, screen: String) {
        let f = app.textFields[fieldID].firstMatch
        XCTAssertTrue(f.waitForExistence(timeout: 10), "\(fieldID) not found on \(screen)")
        f.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "keyboard didn't open on \(screen)")
        let done = app.buttons["keyboardDone"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "no Done button above the keyboard on \(screen)")
        done.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 10), "keyboard stayed up on \(screen)")
    }

    func testInvalidInputShowsAMessageAndNeverNaN() {
        launch()
        tap("clearExample")
        openRow(0)
        type("editor.price", "1.2.3")
        dismissKeyboard()
        XCTAssertTrue(element("editor.error.price").waitForExistence(timeout: 5), "price error message missing")
        closeEditor()
        XCTAssertEqual(text("row0.cost"), "—")
        XCTAssertTrue(element("row0.error").exists, "row should show what's wrong")
        type("menuPrice", "0")
        dismissKeyboard()
        XCTAssertTrue(element("menuError").exists, "menu price error missing")
        XCTAssertEqual(text("bevCostPct"), "—")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'NaN'")).firstMatch.exists, "NaN shown")
    }

    func testTargetOutsideOneTo99IsRejectedWithAMessage() {
        launch()
        type("targetPct", "100")
        dismissKeyboard()
        XCTAssertTrue(element("targetError").waitForExistence(timeout: 5), "100% target should be rejected")
        XCTAssertEqual(text("suggestedPrice"), "—")
        type("targetPct", "20")
        dismissKeyboard()
        XCTAssertFalse(element("targetError").exists)
        XCTAssertEqual(text("suggestedPrice"), "$18.47")
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
        XCTAssertTrue(element("open.Classic Margarita").waitForExistence(timeout: 5), "saved recipe missing from list")
    }

    func testSaveToLibraryShowsUpInMyIngredients() {
        launch()
        openRow(0)
        tap("editor.saveToLibrary")
        XCTAssertTrue(element("editor.tag").waitForExistence(timeout: 5), "row 1 isn't linked to My Ingredients")
        closeEditor()
        XCTAssertTrue(element("row0.tag").waitForExistence(timeout: 5))
        goTo("Ingredients", sidebarID: "sidebar.ingredients")
        XCTAssertTrue(element("lib.Blanco tequila").waitForExistence(timeout: 5), "saved ingredient missing from My Ingredients")
        XCTAssertEqual(text("lib.Blanco tequila.used"), "Not in a recipe")
    }

    func testAddAnIngredientInMyIngredients() {
        launch()
        goTo("Ingredients", sidebarID: "sidebar.ingredients")
        tap("libAdd")
        XCTAssertTrue(field("libEditor.name").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["libEditor.save"].isEnabled, "Save should wait for valid details")
        type("libEditor.name", "Campari")
        type("libEditor.price", "29.99")
        dismissKeyboard()
        XCTAssertTrue(app.buttons["libEditor.save"].isEnabled)
        tap("libEditor.save")
        XCTAssertTrue(element("lib.Campari").waitForExistence(timeout: 5), "new ingredient missing from the list")
    }

    /// Opens a saved 24-ingredient recipe, adds the 25th, and checks the limit is enforced.
    func testIngredientLimitIs25() {
        let lines = (1...24).map {
            #"{"id":"l\#($0)","name":"Item \#($0)","price":"10","size":"750","sizeUnit":"ml","amount":"1","amountUnit":"floz"}"#
        }.joined(separator: ",")
        let seed = #"{"app":"jigger","version":1,"library":[],"recipes":[{"id":"big","name":"Punch Bowl","menuPrice":"12","lines":[\#(lines)]}]}"#
        launch(seed: seed)
        goTo("Recipes", sidebarID: "sidebar.recipes")
        tap("open.Punch Bowl")
        XCTAssertTrue(element("row23").waitForExistence(timeout: 5), "saved recipe didn't open with its 24 ingredients")
        tap("addIngredient")
        XCTAssertTrue(field("editor.name").waitForExistence(timeout: 5))
        closeEditor()
        XCTAssertTrue(element("row24").waitForExistence(timeout: 5), "25th ingredient wasn't added")
        XCTAssertTrue(element("limitNote").waitForExistence(timeout: 5), "25-ingredient note missing")
        XCTAssertFalse(app.buttons["addIngredient"].isEnabled, "Add ingredient still enabled at 25")
        XCTAssertFalse(app.buttons["addFromLibrary"].isEnabled, "Add from My Ingredients still enabled at 25")
    }

    func testMoveAnIngredientToTheTop() {
        launch()
        // Touch and hold the ingredient's name, as a finger would.
        let name = app.staticTexts["row4.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        if !name.isHittable { app.swipeUp() }
        name.press(forDuration: 1.5)
        let moveToTop = app.buttons["Move to top"].firstMatch
        XCTAssertTrue(moveToTop.waitForExistence(timeout: 5), "row menu didn't open")
        moveToTop.tap()
        XCTAssertEqual(text("row0.name"), "Lime (garnish wheel)", "ingredient didn't move to the top")
        XCTAssertEqual(text("drinkCost"), "$3.69", "reordering changed the cost")
    }

    func testReorderListOpensFromTheIngredientsHeader() {
        launch()
        tap("reorder")
        XCTAssertTrue(element("reorder.0").waitForExistence(timeout: 5), "reorder list didn't open")
        tap("reorderDone")
        XCTAssertTrue(element("row0").waitForExistence(timeout: 5))
    }

    func testWasteForAllIngredientsIsVisibleAndApplies() {
        launch()
        type("recipeWaste", "10")
        dismissKeyboard()
        XCTAssertEqual(text("drinkCost"), "$4.10", "10% waste should divide the $3.69 cost by 0.9")
    }

    /// The app fills the whole screen (no compatibility letterboxing, e.g. on iPhone Duo), and the keyboard
    /// lines up with it.
    func testAppFillsTheScreenAndTheKeyboardLinesUp() {
        launch()
        let window = app.windows.firstMatch
        let screen = UIScreen.main.bounds
        XCTAssertEqual(window.frame.width, screen.width, accuracy: 1, "app window is narrower than the screen")
        XCTAssertEqual(window.frame.height, screen.height, accuracy: 1, "app window is shorter than the screen")
        let f = field("menuPrice")
        XCTAssertTrue(f.waitForExistence(timeout: 5))
        f.tap()
        let keyboard = app.keyboards.firstMatch
        if keyboard.waitForExistence(timeout: 5) { // no keyboard when a hardware keyboard is attached
            XCTAssertEqual(keyboard.frame.width, window.frame.width, accuracy: 1, "keyboard doesn't match the app's width")
            XCTAssertEqual(keyboard.frame.minX, window.frame.minX, accuracy: 1, "keyboard is offset from the app")
            dismissKeyboard()
        }
    }

    /// iPad: sidebar navigation with the calculator and summary side by side.
    func testIPadShowsSidebarAndSummaryBesideTheCalculator() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layout only")
        launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(element("sidebar.recipes").waitForExistence(timeout: 5))
        let row = element("row0"), cost = app.staticTexts["drinkCost"]
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(cost.isHittable)
        XCTAssertGreaterThan(cost.frame.minX, row.frame.maxX - 1, "summary should sit to the right of the ingredients")
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }
}
