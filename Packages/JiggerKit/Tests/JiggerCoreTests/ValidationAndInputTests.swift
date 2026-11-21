import XCTest
import JiggerEngine
@testable import JiggerCore

/// Input checks that keep people from entering things that make no sense, and the helpers behind the
/// native editors (pour stepper, duplicate, input cleaning).
final class ValidationAndInputTests: XCTestCase {
    private func line(_ amount: String, size: String = "750", sizeUnit: String = "ml", waste: String = "") -> LineInput {
        LineInput(id: "a", price: "30", size: size, sizeUnit: sizeUnit, amount: amount, amountUnit: "floz", wastePct: waste)
    }

    // MARK: Target beverage cost

    func testTargetMustBeBetween1And99() {
        for bad in ["0", "0.5", "-5", "100", "120"] {
            let t = recipeTotals(RecipeInput(lines: [line("1")], targetPct: bad))
            XCTAssertEqual(t.targetError, "Target must be between 1 and 99%", "target \(bad)")
            XCTAssertNil(t.suggestedPrice, "target \(bad)")
        }
        XCTAssertEqual(checkTargetPct("abc").error, "Enter a percentage like 20")
        XCTAssertNil(checkTargetPct("20").error)
        XCTAssertNil(checkTargetPct("").error, "blank is allowed (no suggested price yet)")
    }

    func testUnusualTargetsGetANoteButStillWork() {
        let low = recipeTotals(RecipeInput(lines: [line("1")], targetPct: "5"))
        XCTAssertNil(low.targetError)
        XCTAssertNotNil(low.targetNote)
        XCTAssertNotNil(low.suggestedPrice)
        XCTAssertNotNil(recipeTotals(RecipeInput(lines: [line("1")], targetPct: "60")).targetNote)
        XCTAssertNil(recipeTotals(RecipeInput(lines: [line("1")], targetPct: "22")).targetNote)
    }

    func testDefaultTargetInSettingsUsesTheSameRule() {
        let s = makeStore()
        XCTAssertFalse(s.setDefaultTarget("100"))
        XCTAssertFalse(s.setDefaultTarget("0"))
        XCTAssertFalse(s.setDefaultTarget(""))
        XCTAssertTrue(s.setDefaultTarget("24"))
        XCTAssertEqual(s.settings.targetPct, "24")
    }

    // MARK: Menu price and servings

    func testMenuPriceBelowCostIsFlagged() {
        // 1 oz of a $30 750 mL bottle costs $1.18; a $1 menu price loses money on every drink.
        let t = recipeTotals(RecipeInput(lines: [line("1")], menuPrice: "1"))
        XCTAssertNil(t.menuError)
        XCTAssertEqual(roundMoney(t.menuBelowCostBy), Decimal(string: "0.18"))
        XCTAssertNil(recipeTotals(RecipeInput(lines: [line("1")], menuPrice: "12")).menuBelowCostBy)
    }

    func testServingsMustBeWholeAndReasonable() {
        XCTAssertEqual(recipeTotals(RecipeInput(lines: [], servings: "2.5")).servingsError, "Whole drinks only, like 25")
        XCTAssertEqual(recipeTotals(RecipeInput(lines: [], servings: "20000")).servingsError, "Up to 10,000 drinks per batch")
        XCTAssertNil(recipeTotals(RecipeInput(lines: [], servings: "100")).servingsError)
        XCTAssertEqual(recipeTotals(RecipeInput(lines: [], servings: "2.5")).servings, 1, "an invalid batch falls back to 1")
    }

    // MARK: Line warnings

    func testPourBiggerThanThePackageIsWarnedButCounted() {
        let r = lineCost(line("30", size: "750")) // 30 fl oz ≈ 887 mL from a 750 mL bottle
        XCTAssertEqual(r.status, .ok)
        XCTAssertNotNil(r.warnings[.amount])
        XCTAssertTrue(lineCost(line("2")).warnings.isEmpty)
    }

    func testVeryHighWasteIsWarned() {
        XCTAssertNotNil(lineCost(line("1", waste: "60")).warnings[.waste])
        XCTAssertNil(lineCost(line("1", waste: "10")).warnings[.waste])
        XCTAssertNotNil(lineCost(line("1", waste: "100")).errors[.waste], "100% waste is still an error")
    }

    // MARK: Typing

    func testNumberFieldsDropLettersAndSymbols() {
        XCTAssertEqual(sanitizeNumericInput("$24.99abc", decimalSeparator: ".", allowFraction: false), "24.99")
        XCTAssertEqual(sanitizeNumericInput("24,99", decimalSeparator: ",", allowFraction: false), "24.99")
        XCTAssertEqual(sanitizeNumericInput("1 1/2", decimalSeparator: ".", allowFraction: false), "112")
        XCTAssertEqual(sanitizeNumericInput("1 1/2 oz", decimalSeparator: ".", allowFraction: true), "1 1/2 ")
        let s = makeStore()
        XCTAssertEqual(s.normalizeTyped("12%"), "12")
        XCTAssertEqual(s.normalizePour("1/2"), "1/2")
    }

    // MARK: Editors

    func testPourStepperMovesInQuarterOuncesAndNeverBelowZero() {
        let s = makeStore()
        let id = s.draft.lines[0].id
        s.setLine(id, .amount, "1")
        s.stepPour(id, by: 1)
        XCTAssertEqual(s.draft.lines[0].amount, "1.25")
        s.stepPour(id, by: -10)
        XCTAssertEqual(s.draft.lines[0].amount, "0")
    }

    func testPourStepperUsesFiveMillilitresWhenShowingML() {
        let s = makeStore()
        s.setDisplayUnit("ml")
        let id = s.draft.lines[0].id
        s.setLine(id, .amount, "30")
        s.stepPour(id, by: 2)
        XCTAssertEqual(s.draft.lines[0].amount, "40")
        XCTAssertEqual(s.draft.lines[0].amountUnit, "ml")
    }

    func testDuplicateLineCopiesBelowTheOriginal() {
        let s = makeStore()
        let first = s.draft.lines[0].id
        let before = s.draft.lines.count
        s.setLine(first, .name, "Gin")
        let copy = s.duplicateLine(first)
        XCTAssertEqual(s.draft.lines.count, before + 1)
        XCTAssertEqual(s.draft.lines[1].id, copy)
        XCTAssertEqual(s.draft.lines[1].name, "Gin")
        XCTAssertNotEqual(copy, first)
    }

    func testLibraryEditorMessages() {
        let s = makeStore()
        let empty = s.libraryFieldMessages(name: " ", price: "", size: "0", sizeUnit: "ml")
        XCTAssertEqual(empty[.name], "Enter a name")
        XCTAssertEqual(empty[.price], "Enter the price you pay")
        XCTAssertEqual(empty[.size], "Size must be more than 0")
        XCTAssertTrue(s.addLibraryItem(name: "Campari", price: "29.99", size: "750", sizeUnit: .ml))
        XCTAssertEqual(s.libraryFieldMessages(name: "campari ", price: "30", size: "750", sizeUnit: "ml")[.name],
                       "Already in My Ingredients with this package size")
        XCTAssertTrue(s.libraryFieldMessages(name: "Campari", price: "30", size: "1", sizeUnit: "l").isEmpty)
    }
}
