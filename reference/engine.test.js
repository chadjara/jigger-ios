const test = require("node:test");
const assert = require("node:assert/strict");
const E = require("./engine.js");
const { D } = E;

const money = (d) => E.roundMoney(d).toFixed(2);
const line = (o) => ({ id: "x", price: "", size: "", sizeUnit: "ml", amount: "", amountUnit: "floz", wastePct: "", ...o });

test("parse handles currency symbols, commas, fractions, blanks, junk", () => {
  assert.equal(E.parse("$24.99").toString(), "24.99");
  assert.equal(E.parse("1,000").toString(), "1000");
  assert.equal(E.parse(".5").toString(), "0.5");
  assert.equal(E.parse("1/2").toString(), "0.5");
  assert.equal(E.parse("1 1/2").toString(), "1.5");
  assert.equal(E.parse("  "), null);
  assert.ok(E.isInvalid(E.parse("abc")));
  assert.ok(E.isInvalid(E.parse("1/0")));
  assert.ok(E.isInvalid(E.parse("1.2.3")));
});

test("2 oz from a $24.99 750 mL bottle", () => {
  const r = E.lineCost(line({ price: "24.99", size: "750", amount: "2" }));
  assert.equal(r.status, "ok");
  // 2 × 29.5735295625 / 750 × 24.99 = 1.97077...
  assert.equal(money(r.cost), "1.97");
  assert.ok(r.cost.minus("1.970779969...".replace("...", "")).abs().lt("0.000001"));
});

test("mL pour from a 1.75 L bottle (L package unit)", () => {
  const r = E.lineCost(line({ price: "35", size: "1.75", sizeUnit: "l", amount: "45", amountUnit: "ml" }));
  assert.equal(r.cost.toString(), "0.9"); // 45/1750*35 exactly
});

test("same pour in oz and in exact mL costs the same", () => {
  const a = E.lineCost(line({ price: "30", size: "750", amount: "1.5" })).cost;
  const b = E.lineCost(line({ price: "30", size: "750", amount: "44.36029434375", amountUnit: "ml" })).cost;
  assert.equal(a.toString(), b.toString());
});

test("half a lime at $0.50 each costs $0.25", () => {
  const r = E.lineCost(line({ price: "0.50", size: "1", sizeUnit: "each", amount: "1/2", amountUnit: "each" }));
  assert.equal(r.cost.toString(), "0.25");
});

test("case of 40 limes, 0.25 each", () => {
  const r = E.lineCost(line({ price: "12", size: "40", sizeUnit: "each", amount: "0.25", amountUnit: "each" }));
  assert.equal(r.cost.toString(), "0.075");
});

test("weight: 10 g of sugar from a 2 lb bag", () => {
  const r = E.lineCost(line({ price: "3.00", size: "2", sizeUnit: "lb", amount: "10", amountUnit: "g" }));
  // 3 / 907.18474 × 10
  assert.equal(money(r.cost), "0.03");
  assert.ok(r.cost.minus(new D(30).div("907.18474")).abs().lt("1e-30"));
});

test("weight ounces are not fluid ounces", () => {
  const wt = E.lineCost(line({ price: "16", size: "1", sizeUnit: "lb", amount: "1", amountUnit: "ozwt" }));
  assert.equal(wt.cost.toString(), "1"); // 1 oz wt = 1/16 lb
  const bad = E.lineCost(line({ price: "16", size: "1", sizeUnit: "lb", amount: "1", amountUnit: "floz" }));
  assert.equal(bad.status, "invalid");
  assert.match(bad.errors.amount, /weight/);
});

test("waste is a yield loss: 10% waste divides by 0.9", () => {
  const r = E.lineCost(line({ price: "27", size: "750", sizeUnit: "ml", amount: "25", amountUnit: "ml", wastePct: "10" }));
  assert.equal(r.cost.toString(), "1"); // 0.9 / 0.9
});

test("line waste overrides recipe waste; blank line waste uses recipe waste", () => {
  const recipe = { wastePct: "10", lines: [
    { ...line({ price: "27", size: "750", amount: "25", amountUnit: "ml" }), id: "a" },
    { ...line({ price: "27", size: "750", amount: "25", amountUnit: "ml", wastePct: "0" }), id: "b" },
  ] };
  const t = E.recipeTotals(recipe);
  assert.equal(t.lines[0].cost.toString(), "1");
  assert.equal(t.lines[1].cost.toString(), "0.9");
});

test("invalid inputs are reported, never thrown", () => {
  const r = E.lineCost(line({ price: "-1", size: "0", amount: "x", wastePct: "100" }));
  assert.equal(r.status, "invalid");
  assert.ok(r.errors.price && r.errors.size && r.errors.amount && r.errors.waste);
});

test("incomplete lines are excluded and counted", () => {
  const t = E.recipeTotals({ lines: [line({ id: "a", price: "10" }), line({ id: "b", price: "30", size: "750", amount: "25", amountUnit: "ml" })], targetPct: "20" });
  assert.equal(t.incomplete, 1);
  assert.equal(t.counted, 1);
  assert.equal(t.drinkCost.toString(), "1");
  assert.equal(t.suggestedPrice.toString(), "5");
});

test("suggested price, beverage cost %, gross profit and margin", () => {
  const t = E.recipeTotals({
    lines: [line({ id: "a", price: "90", size: "750", amount: "25", amountUnit: "ml" })], // $3.00
    targetPct: "20", menuPrice: "12",
  });
  assert.equal(t.drinkCost.toString(), "3");
  assert.equal(t.suggestedPrice.toString(), "15");
  assert.equal(t.bevCostPct.toString(), "25");
  assert.equal(t.grossProfit.toString(), "9");
  assert.equal(t.grossMargin.toString(), "75");
});

test("bev cost % + gross margin always total 100", () => {
  const t = E.recipeTotals({ lines: [line({ id: "a", price: "24.99", size: "750", amount: "2" })], menuPrice: "13" });
  assert.equal(t.bevCostPct.plus(t.grossMargin).toString(), "100");
});

test("additional costs add to drink cost; bad extras are flagged", () => {
  const t = E.recipeTotals({ lines: [], extras: { napkins: "0.02", straws: "0.03", cups: "abc" }, targetPct: "20" });
  assert.equal(t.extrasCost.toString(), "0.05");
  assert.equal(t.drinkCost.toString(), "0.05");
  assert.ok(t.extrasErrors.cups);
  assert.equal(t.suggestedPrice.toString(), "0.25");
});

test("division by zero and bad percentages are guarded", () => {
  const base = { lines: [line({ id: "a", price: "30", size: "750", amount: "25", amountUnit: "ml" })] };
  for (const pct of ["0", "-5", "120"]) {
    const t = E.recipeTotals({ ...base, targetPct: pct });
    assert.equal(t.suggestedPrice, null);
    assert.ok(t.targetError);
  }
  const t2 = E.recipeTotals({ ...base, menuPrice: "0" });
  assert.equal(t2.bevCostPct, null);
  assert.ok(t2.menuError);
  const empty = E.recipeTotals({ lines: [], targetPct: "20", menuPrice: "10" });
  assert.equal(empty.suggestedPrice, null);
  assert.equal(empty.bevCostPct, null);
});

test("batch scaling multiplies per-drink values without rounding first", () => {
  const t = E.recipeTotals({ lines: [line({ id: "a", price: "24.99", size: "750", amount: "2" })], servings: "100", menuPrice: "12" });
  // per drink 1.9707799…; 100 drinks = 197.08 (not 1.97 × 100 = 197.00)
  assert.equal(money(t.batchCost), "197.08");
  assert.equal(t.batchRevenue.toString(), "1200");
  const bad = E.recipeTotals({ lines: [], servings: "0" });
  assert.ok(bad.servingsError);
});

test("no float accumulation across many small lines", () => {
  const lines = Array.from({ length: 25 }, (_, i) => line({ id: "l" + i, price: "0.1", size: "1", sizeUnit: "each", amount: "1", amountUnit: "each" }));
  const t = E.recipeTotals({ lines });
  assert.equal(t.drinkCost.toString(), "2.5");
});

test("pour display uses bar convention and never drifts on repeated toggles", () => {
  assert.equal(E.displayPour("1.5", "floz", "ml"), "45");
  assert.equal(E.displayPour("0.75", "floz", "ml"), "22.5");
  assert.equal(E.displayPour("60", "ml", "floz"), "2");
  assert.equal(E.displayPour("50", "ml", "floz"), "1.67");
  // display always derives from source, so toggling 100 times changes nothing
  let shown = "1.5";
  for (let i = 0; i < 100; i++) shown = i % 2 ? E.displayPour("1.5", "floz", "floz") : E.displayPour("1.5", "floz", "ml");
  assert.equal(E.displayPour("1.5", "floz", "ml"), "45");
});

test("money formatting rounds half up at 2 places and supports other currencies", () => {
  assert.equal(E.formatMoney(new D("2.345"), "USD"), "$2.35");
  assert.equal(E.formatMoney(new D("18.4677"), "EUR", "en-US"), "€18.47");
  assert.equal(E.formatMoney(null), "—");
  assert.equal(E.formatPct(new D("26.3888")), "26.4%");
});
