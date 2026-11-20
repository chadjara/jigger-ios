import XCTest
@testable import JiggerEngine

/// A one-to-one port of reference/engine.test.js: same inputs, same expected values.
final class EngineTests: XCTestCase {
    private func money(_ d: Decimal?) -> String { fixed(roundMoney(d)!, places: 2) }
    private func str(_ d: Decimal?) -> String { plainString(d!) }
    private func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }
    private func line(id: String = "x", price: String = "", size: String = "", sizeUnit: String = "ml",
                      amount: String = "", amountUnit: String = "floz", wastePct: String = "") -> LineInput {
        LineInput(id: id, price: price, size: size, sizeUnit: sizeUnit, amount: amount, amountUnit: amountUnit, wastePct: wastePct)
    }

    func testParseHandlesCurrencySymbolsCommasFractionsBlanksJunk() {
        XCTAssertEqual(str(parseNumber("$24.99").value), "24.99")
        XCTAssertEqual(str(parseNumber("1,000").value), "1000")
        XCTAssertEqual(str(parseNumber(".5").value), "0.5")
        XCTAssertEqual(str(parseNumber("1/2").value), "0.5")
        XCTAssertEqual(str(parseNumber("1 1/2").value), "1.5")
        XCTAssertEqual(parseNumber("  "), .blank)
        XCTAssertTrue(parseNumber("abc").isInvalid)
        XCTAssertTrue(parseNumber("1/0").isInvalid)
        XCTAssertTrue(parseNumber("1.2.3").isInvalid)
    }

    func test2OzFromA2499_750mLBottle() {
        let r = lineCost(line(price: "24.99", size: "750", amount: "2"))
        XCTAssertEqual(r.status, .ok)
        // 2 × 29.5735295625 / 750 × 24.99 = 1.97077...
        XCTAssertEqual(money(r.cost), "1.97")
        XCTAssertLessThan(abs(r.cost! - dec("1.970779969")), dec("0.000001"))
    }

    func testMLPourFromA175LBottle() {
        let r = lineCost(line(price: "35", size: "1.75", sizeUnit: "l", amount: "45", amountUnit: "ml"))
        XCTAssertEqual(str(r.cost), "0.9") // 45/1750*35 exactly
    }

    func testSamePourInOzAndInExactMLCostsTheSame() {
        let a = lineCost(line(price: "30", size: "750", amount: "1.5")).cost
        let b = lineCost(line(price: "30", size: "750", amount: "44.36029434375", amountUnit: "ml")).cost
        XCTAssertEqual(str(a), str(b))
    }

    func testHalfALimeAt50CentsEachCosts25Cents() {
        let r = lineCost(line(price: "0.50", size: "1", sizeUnit: "each", amount: "1/2", amountUnit: "each"))
        XCTAssertEqual(str(r.cost), "0.25")
    }

    func testCaseOf40Limes() {
        let r = lineCost(line(price: "12", size: "40", sizeUnit: "each", amount: "0.25", amountUnit: "each"))
        XCTAssertEqual(str(r.cost), "0.075")
    }

    func testWeight10gOfSugarFromA2lbBag() {
        let r = lineCost(line(price: "3.00", size: "2", sizeUnit: "lb", amount: "10", amountUnit: "g"))
        // 3 / 907.18474 × 10
        XCTAssertEqual(money(r.cost), "0.03")
        XCTAssertLessThan(abs(r.cost! - Decimal(30) / dec("907.18474")), dec("1e-30"))
    }

    func testWeightOuncesAreNotFluidOunces() {
        let wt = lineCost(line(price: "16", size: "1", sizeUnit: "lb", amount: "1", amountUnit: "ozwt"))
        XCTAssertEqual(str(wt.cost), "1") // 1 oz wt = 1/16 lb
        let bad = lineCost(line(price: "16", size: "1", sizeUnit: "lb", amount: "1", amountUnit: "floz"))
        XCTAssertEqual(bad.status, .invalid)
        XCTAssertTrue(bad.errors[.amount]!.contains("weight"))
    }

    func testWasteIsAYieldLoss() {
        let r = lineCost(line(price: "27", size: "750", sizeUnit: "ml", amount: "25", amountUnit: "ml", wastePct: "10"))
        XCTAssertEqual(str(r.cost), "1") // 0.9 / 0.9
    }

    func testLineWasteOverridesRecipeWaste() {
        let recipe = RecipeInput(lines: [
            line(id: "a", price: "27", size: "750", amount: "25", amountUnit: "ml"),
            line(id: "b", price: "27", size: "750", amount: "25", amountUnit: "ml", wastePct: "0"),
        ], wastePct: "10")
        let t = recipeTotals(recipe)
        XCTAssertEqual(str(t.lines[0].cost), "1")
        XCTAssertEqual(str(t.lines[1].cost), "0.9")
    }

    func testInvalidInputsAreReportedNeverThrown() {
        let r = lineCost(line(price: "-1", size: "0", amount: "x", wastePct: "100"))
        XCTAssertEqual(r.status, .invalid)
        XCTAssertNotNil(r.errors[.price]); XCTAssertNotNil(r.errors[.size])
        XCTAssertNotNil(r.errors[.amount]); XCTAssertNotNil(r.errors[.waste])
    }

    func testIncompleteLinesAreExcludedAndCounted() {
        let t = recipeTotals(RecipeInput(lines: [
            line(id: "a", price: "10"),
            line(id: "b", price: "30", size: "750", amount: "25", amountUnit: "ml"),
        ], targetPct: "20"))
        XCTAssertEqual(t.incomplete, 1)
        XCTAssertEqual(t.counted, 1)
        XCTAssertEqual(str(t.drinkCost), "1")
        XCTAssertEqual(str(t.suggestedPrice), "5")
    }

    func testSuggestedPriceBevCostGrossProfitAndMargin() {
        let t = recipeTotals(RecipeInput(lines: [line(id: "a", price: "90", size: "750", amount: "25", amountUnit: "ml")],
                                         targetPct: "20", menuPrice: "12"))
        XCTAssertEqual(str(t.drinkCost), "3")
        XCTAssertEqual(str(t.suggestedPrice), "15")
        XCTAssertEqual(str(t.bevCostPct), "25")
        XCTAssertEqual(str(t.grossProfit), "9")
        XCTAssertEqual(str(t.grossMargin), "75")
    }

    func testBevCostPlusGrossMarginAlwaysTotal100() {
        let t = recipeTotals(RecipeInput(lines: [line(id: "a", price: "24.99", size: "750", amount: "2")], menuPrice: "13"))
        XCTAssertEqual(str(t.bevCostPct! + t.grossMargin!), "100")
    }

    func testAdditionalCostsAddToDrinkCostBadExtrasAreFlagged() {
        let t = recipeTotals(RecipeInput(lines: [], extras: ["napkins": "0.02", "straws": "0.03", "cups": "abc"], targetPct: "20"))
        XCTAssertEqual(str(t.extrasCost), "0.05")
        XCTAssertEqual(str(t.drinkCost), "0.05")
        XCTAssertNotNil(t.extrasErrors["cups"])
        XCTAssertEqual(str(t.suggestedPrice), "0.25")
    }

    func testDivisionByZeroAndBadPercentagesAreGuarded() {
        let base = RecipeInput(lines: [line(id: "a", price: "30", size: "750", amount: "25", amountUnit: "ml")])
        for pct in ["0", "-5", "120"] {
            var r = base; r.targetPct = pct
            let t = recipeTotals(r)
            XCTAssertNil(t.suggestedPrice)
            XCTAssertNotNil(t.targetError)
        }
        var r2 = base; r2.menuPrice = "0"
        let t2 = recipeTotals(r2)
        XCTAssertNil(t2.bevCostPct)
        XCTAssertNotNil(t2.menuError)
        let empty = recipeTotals(RecipeInput(lines: [], targetPct: "20", menuPrice: "10"))
        XCTAssertNil(empty.suggestedPrice)
        XCTAssertNil(empty.bevCostPct)
    }

    func testBatchScalingMultipliesWithoutRoundingFirst() {
        let t = recipeTotals(RecipeInput(lines: [line(id: "a", price: "24.99", size: "750", amount: "2")], menuPrice: "12", servings: "100"))
        // per drink 1.9707799…; 100 drinks = 197.08 (not 1.97 × 100 = 197.00)
        XCTAssertEqual(money(t.batchCost), "197.08")
        XCTAssertEqual(str(t.batchRevenue), "1200")
        let bad = recipeTotals(RecipeInput(lines: [], servings: "0"))
        XCTAssertNotNil(bad.servingsError)
    }

    func testNoFloatAccumulationAcrossManySmallLines() {
        let lines = (0..<25).map { line(id: "l\($0)", price: "0.1", size: "1", sizeUnit: "each", amount: "1", amountUnit: "each") }
        XCTAssertEqual(str(recipeTotals(RecipeInput(lines: lines)).drinkCost), "2.5")
    }

    func testPourDisplayUsesBarConventionAndNeverDrifts() {
        XCTAssertEqual(displayPour("1.5", from: "floz", to: "ml"), "45")
        XCTAssertEqual(displayPour("0.75", from: "floz", to: "ml"), "22.5")
        XCTAssertEqual(displayPour("60", from: "ml", to: "floz"), "2")
        XCTAssertEqual(displayPour("50", from: "ml", to: "floz"), "1.67")
        // display always derives from source, so toggling 100 times changes nothing
        var shown = "1.5"
        for i in 0..<100 { shown = i % 2 == 1 ? displayPour("1.5", from: "floz", to: "floz") : displayPour("1.5", from: "floz", to: "ml") }
        XCTAssertEqual(shown, "1.5")
        XCTAssertEqual(displayPour("1.5", from: "floz", to: "ml"), "45")
    }

    func testMoneyFormattingRoundsHalfUpAndSupportsOtherCurrencies() {
        XCTAssertEqual(formatMoney(dec("2.345"), currency: "USD"), "$2.35")
        XCTAssertEqual(formatMoney(dec("18.4677"), currency: "EUR", locale: Locale(identifier: "en_US")), "€18.47")
        XCTAssertEqual(formatMoney(nil), "—")
        XCTAssertEqual(formatPct(dec("26.3888")), "26.4%")
    }
}

/// Extra engine coverage beyond the web suite: the cost-sheet analysis and edge cases.
final class EngineExtrasTests: XCTestCase {
    private func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

    func testPriceLadderAndBiggestDriver() {
        let t = recipeTotals(RecipeInput(lines: [
            LineInput(id: "a", price: "90", size: "750", sizeUnit: "ml", amount: "25", amountUnit: "ml"), // 3.00
            LineInput(id: "b", price: "30", size: "750", sizeUnit: "ml", amount: "25", amountUnit: "ml"), // 1.00
        ]))
        let ladder = priceLadder(t)
        XCTAssertEqual(ladder.map { fixed($0.price, places: 2) }, ["22.22", "20.00", "18.18", "16.00"])
        XCTAssertEqual(biggestCostDriver(t)?.id, "a")
        XCTAssertTrue(priceLadder(recipeTotals(RecipeInput())).isEmpty)
        XCTAssertNil(biggestCostDriver(recipeTotals(RecipeInput())))
    }

    func testUnitCostIsExactPerPourUnit() {
        // $24.99 for 750 mL: 24.99 × 29.5735295625 / 750 per fl oz
        let oz = unitCost(price: "24.99", size: "750", sizeUnit: "ml")!
        XCTAssertEqual(oz.basis, .fluidOunce)
        XCTAssertEqual(oz.amount, dec("24.99") * dec("29.5735295625") / 750)
        XCTAssertEqual(fixed(oz.amount, places: 2), "0.99")
        XCTAssertEqual(unitCost(price: "24.99", size: "750", sizeUnit: "ml", volumeDisplayUnit: "ml")?.basis, .tenMilliliters)
        XCTAssertEqual(fixed(unitCost(price: "35", size: "1.75", sizeUnit: "l", volumeDisplayUnit: "ml")!.amount, places: 2), "0.20")
        // 1 lb at $16 is exactly $1 per oz wt
        XCTAssertEqual(unitCost(price: "16", size: "1", sizeUnit: "lb")?.amount, 1)
        XCTAssertEqual(unitCost(price: "12", size: "40", sizeUnit: "each")?.amount, dec("0.3"))
        XCTAssertNil(unitCost(price: "abc", size: "750", sizeUnit: "ml"))
        XCTAssertNil(unitCost(price: "10", size: "0", sizeUnit: "ml"))
        XCTAssertNil(unitCost(price: "10", size: "750", sizeUnit: "barrel"))
    }

    func testParserEdgeCases() {
        XCTAssertEqual(parseNumber(nil), .blank)
        XCTAssertEqual(parseNumber("5."), .value(5))
        XCTAssertEqual(parseNumber("-.5"), .value(dec("-0.5")))
        XCTAssertEqual(parseNumber("24.99 $"), .value(dec("24.99")))
        XCTAssertEqual(parseNumber("€ 3"), .value(3))
        XCTAssertTrue(parseNumber("1 1/0").isInvalid)
        XCTAssertTrue(parseNumber("٣").isInvalid) // non-ASCII digits are not accepted
        XCTAssertTrue(parseNumber("1e5").isInvalid)
    }

    func testUnknownUnitsAreReportedNotCrashed() {
        let r = lineCost(LineInput(price: "1", size: "1", sizeUnit: "barrel", amount: "1", amountUnit: "pinch"))
        XCTAssertEqual(r.status, .invalid)
        XCTAssertEqual(r.errors[.size], "Choose a package unit")
        XCTAssertEqual(r.errors[.amount], "Choose a unit")
    }

    func testRecipeWasteInvalidFlagsLinesWithoutTheirOwn() {
        let t = recipeTotals(RecipeInput(lines: [LineInput(id: "a", price: "27", size: "750", sizeUnit: "ml", amount: "25", amountUnit: "ml")], wastePct: "abc"))
        XCTAssertEqual(t.lines[0].status, .invalid)
        XCTAssertNotNil(t.lines[0].errors[.waste])
    }

    func testFixedPadsAndRoundsNegatives() {
        XCTAssertEqual(fixed(dec("2.5"), places: 2), "2.50")
        XCTAssertEqual(fixed(3, places: 1), "3.0")
        XCTAssertEqual(fixed(dec("-1.005"), places: 2), "-1.01")
        XCTAssertEqual(formatMoney(dec("-0.004")), "$0.00")
    }
}
