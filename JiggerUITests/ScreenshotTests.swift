import XCTest

/// Captures App Store screenshots. Skipped in normal CI; the Screenshots workflow runs it with
/// TEST_RUNNER_JIGGER_SCREENSHOTS=1 on the 6.9" iPhone, 13" iPad and iPhone Duo simulators and exports the images.
/// TEST_RUNNER_JIGGER_SCREENSHOT_DEVICE names the files' prefix (e.g. "Duo"); otherwise iPhone or iPad.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JIGGER_SCREENSHOTS"] == "1",
                          "Runs only in the Screenshots workflow")
        continueAfterFailure = false
    }

    func testAppStoreScreenshots() {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let device = ProcessInfo.processInfo.environment["JIGGER_SCREENSHOT_DEVICE"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (isPad ? "iPad" : "iPhone")
        app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["JIGGER_SEED"] = DemoData.backup
        app.launch()
        XCTAssertTrue(element("recipeName").waitForExistence(timeout: 20))
        // Rotate after launch (set before launch, the simulator reverted to portrait),
        // so the iPad sidebar is on screen.
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(2)
        }

        // Save the Margarita so the "illustrative prices" banner and toast are gone.
        element("saveRecipe").tap()
        waitForToastToClear()

        if isPad {
            snap("\(device)-01-calculator")
            element("servings.25").tap()
            snap("\(device)-02-batch")
            openSidebarItem("sidebar.recipes")
            snap("\(device)-03-recipes")
            openSidebarItem("sidebar.ingredients")
            snap("\(device)-04-ingredients")
        } else {
            snap("\(device)-01-calculator")
            element("showSummary").tap()
            snap("\(device)-02-summary")
            // The batch section sits further down the tab: scroll it into view before choosing 25.
            let servings = element("servings.25")
            var tries = 0
            while !servings.isHittable && tries < 4 {
                dragUp()
                tries += 1
            }
            if !servings.isHittable { dragUp() } // one more so the batch totals show under the chips
            servings.tap()
            snap("\(device)-03-batch")
            openTab("Recipes")
            snap("\(device)-04-recipes")
            openTab("Ingredients")
            snap("\(device)-05-ingredients")
        }
    }

    private func element(_ id: String) -> XCUIElement {
        let e = app.descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(e.waitForExistence(timeout: 10), "\(id) not found")
        return e
    }

    /// Scrolls the screen's content up by about a third of the window, slowly so it stops where it lands.
    private func dragUp() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        start.press(forDuration: 0.1, thenDragTo: end)
        sleep(1)
    }

    /// Taps a tab: the bottom tab bar on iPhone, or Apple's floating tab bar at the top on iPhone Duo
    /// (its tabs are plain buttons).
    private func openTab(_ title: String) {
        let bottom = app.tabBars.buttons[title].firstMatch
        if bottom.waitForExistence(timeout: 3) { return bottom.tap() }
        let floating = app.buttons[title].firstMatch
        XCTAssertTrue(floating.waitForExistence(timeout: 10), "\(title) tab not found")
        floating.tap()
    }

    /// Taps a sidebar entry, revealing the sidebar first if it is collapsed.
    private func openSidebarItem(_ id: String) {
        let item = element(id)
        if !item.isHittable {
            let toggle = app.buttons["ToggleSidebar"].exists ? app.buttons["ToggleSidebar"] : app.buttons["Show Sidebar"]
            if toggle.exists { toggle.tap() }
            _ = item.waitForExistence(timeout: 5)
        }
        item.tap()
    }

    /// Dismisses the "Saved" message (tapping it closes it) and waits for it to go, without failing
    /// the capture if it lingers on a slow simulator.
    private func waitForToastToClear() {
        let toast = app.descendants(matching: .any)["toast"].firstMatch
        if toast.waitForExistence(timeout: 2), toast.isHittable { toast.tap() }
        _ = toast.waitForNonExistence(timeout: 15)
    }

    private func snap(_ name: String) {
        sleep(1) // let scrolling and layout settle
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Demo recipes and ingredients for screenshots, in the app's backup format. Prices are illustrative.
enum DemoData {
    static let backup = #"""
    {"app":"jigger","version":1,
     "library":[
      {"id":"lib-gin","name":"London dry gin","price":"28.00","size":"750","sizeUnit":"ml","createdAt":"2026-11-10T18:00:00.000Z","updatedAt":"2026-11-10T18:00:00.000Z"},
      {"id":"lib-campari","name":"Campari","price":"29.99","size":"750","sizeUnit":"ml","createdAt":"2026-11-10T18:00:00.000Z","updatedAt":"2026-11-10T18:00:00.000Z"},
      {"id":"lib-vermouth","name":"Sweet vermouth","price":"16.00","size":"750","sizeUnit":"ml","createdAt":"2026-11-10T18:00:00.000Z","updatedAt":"2026-11-10T18:00:00.000Z"},
      {"id":"lib-bourbon","name":"Bourbon","price":"34.00","size":"750","sizeUnit":"ml","createdAt":"2026-11-10T18:00:00.000Z","updatedAt":"2026-11-10T18:00:00.000Z"},
      {"id":"lib-vodka","name":"Vodka","price":"24.99","size":"1","sizeUnit":"l","createdAt":"2026-11-10T18:00:00.000Z","updatedAt":"2026-11-10T18:00:00.000Z"},
      {"id":"lib-coffee","name":"Coffee liqueur","price":"22.00","size":"750","sizeUnit":"ml","createdAt":"2026-11-10T18:00:00.000Z","updatedAt":"2026-11-10T18:00:00.000Z"},
      {"id":"lib-orange","name":"Orange","price":"0.60","size":"1","sizeUnit":"each","createdAt":"2026-11-10T18:00:00.000Z","updatedAt":"2026-11-10T18:00:00.000Z"}
     ],
     "recipes":[
      {"id":"demo-negroni","name":"Negroni","menuPrice":"13","targetPct":"20","servings":"1","createdAt":"2026-11-12T19:00:00.000Z","updatedAt":"2026-11-18T19:00:00.000Z",
       "lines":[
        {"id":"n1","libId":"lib-gin","amount":"1","amountUnit":"floz"},
        {"id":"n2","libId":"lib-campari","amount":"1","amountUnit":"floz"},
        {"id":"n3","libId":"lib-vermouth","amount":"1","amountUnit":"floz"},
        {"id":"n4","libId":"lib-orange","amount":"0.25","amountUnit":"each"}]},
      {"id":"demo-oldfashioned","name":"Old Fashioned","menuPrice":"14","targetPct":"20","servings":"1","createdAt":"2026-11-12T19:00:00.000Z","updatedAt":"2026-11-17T19:00:00.000Z",
       "lines":[
        {"id":"o1","libId":"lib-bourbon","amount":"2","amountUnit":"floz"},
        {"id":"o2","name":"Demerara syrup","price":"6.00","size":"500","sizeUnit":"ml","amount":"0.25","amountUnit":"floz"},
        {"id":"o3","name":"Angostura bitters","price":"11.99","size":"200","sizeUnit":"ml","amount":"2","amountUnit":"ml"},
        {"id":"o4","libId":"lib-orange","amount":"0.25","amountUnit":"each"}]},
      {"id":"demo-espresso","name":"Espresso Martini","menuPrice":"15","targetPct":"20","servings":"1","createdAt":"2026-11-12T19:00:00.000Z","updatedAt":"2026-11-16T19:00:00.000Z",
       "lines":[
        {"id":"e1","libId":"lib-vodka","amount":"2","amountUnit":"floz"},
        {"id":"e2","libId":"lib-coffee","amount":"1","amountUnit":"floz"},
        {"id":"e3","name":"Espresso shot","price":"0.40","size":"1","sizeUnit":"each","pkgMode":"custom","amount":"1","amountUnit":"each"},
        {"id":"e4","name":"Simple syrup","price":"4.00","size":"1","sizeUnit":"l","amount":"0.25","amountUnit":"floz"}]}
     ]}
    """#
}
