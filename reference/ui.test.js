const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const { JSDOM, VirtualConsole } = require("jsdom");


let html = fs.readFileSync("/mnt/user-data/outputs/jigger.html", "utf8")
  .replace(/<script src="https:\/\/cdnjs[^"]+"><\/script>/, "<script>" + fs.readFileSync("node_modules/decimal.js/decimal.js", "utf8") + "</script>")
  .replace(/<link[^>]+fonts[^>]+>/g, "");

function boot(storage) {
  const errors = [];
  const vc = new VirtualConsole();
  vc.on("jsdomError", (e) => errors.push(e.message));
  vc.on("error", (e) => errors.push(String(e)));
  const dom = new JSDOM(html, { runScripts: "dangerously", url: "https://example.test/#calculator", virtualConsole: vc, pretendToBeVisual: true,
    beforeParse(w) {
      if (storage) w.localStorage.setItem("jigger.v1", storage);
      w.print = () => {};
      w.scrollTo = () => {};
      w.HTMLElement.prototype.scrollIntoView = () => {};
    } });
  const w = dom.window, d = w.document;
  const $ = (s, el = d) => el.querySelector(s), $$ = (s, el = d) => [...el.querySelectorAll(s)];
  const type = (el, v) => { el.value = v; el.dispatchEvent(new w.Event("input", { bubbles: true })); };
  const choose = (el, v) => { el.value = v; el.dispatchEvent(new w.Event("change", { bubbles: true })); };
  const flush = () => { w.dispatchEvent(new w.Event("pagehide")); return w.localStorage.getItem("jigger.v1"); };
  return { w, d, $, $$, type, choose, flush, errors, S: () => w.__jigger.state };
}
const rows = (t) => t.$$("#rows .row[data-id]");
const field = (t, row, f) => t.$(`[data-f="${f}"]`, row);
const costOf = (t, row) => t.$('[data-out="cost"]', row).textContent;

test("first visit shows the Margarita example with correct totals", () => {
  const t = boot();
  assert.equal(t.$("#recipeName").value, "Classic Margarita");
  assert.equal(t.$("#exampleNotice").hidden, false);
  assert.equal(rows(t).length, 5);
  // tequila 2oz of $32/750 = 2.5236 ; triple 0.5518 ; lime 0.2662 ; agave 0.2514 ; garnish 0.10 => 3.693
  assert.equal(costOf(t, rows(t)[0]), "$2.52");
  assert.equal(t.$("#sDrinkCost").textContent, "$3.69");
  assert.equal(t.$("#sSuggested").textContent, "$18.47");
  assert.equal(t.$("#sBevPct").textContent, "26.4%");
  assert.equal(t.$("#sProfit").textContent, "$10.31");
  assert.equal(t.$("#sMargin").textContent, "73.6%");
  assert.match(t.$("#sCompare").textContent, /below the suggested price/);
  assert.deepEqual(t.errors, []);
});

test("add, fill, remove and undo an ingredient", () => {
  const t = boot();
  t.$("#clearExample").click();
  assert.equal(rows(t).length, 1);
  const r = rows(t)[0];
  type(t, field(t, r, "name"), "Tito’s Vodka");
  t.type(field(t, r, "price"), "24.99");
  t.type(field(t, r, "amount"), "2");
  assert.equal(costOf(t, r), "$1.97");
  assert.equal(t.$("#sDrinkCost").textContent, "$1.97");
  assert.equal(t.$("#sSuggested").textContent, "$9.85");
  t.$("#addRow").click();
  assert.equal(rows(t).length, 2);
  assert.equal(t.d.activeElement, field(t, rows(t)[1], "name"));
  t.$('[data-act="remove"]', rows(t)[0]).click();
  assert.equal(rows(t).length, 1);
  assert.equal(t.$("#sDrinkCost").textContent, "$0.00");
  t.$("#toastUndo").click();
  assert.equal(rows(t).length, 2);
  assert.equal(t.$("#sDrinkCost").textContent, "$1.97");
  function type(tt, el, v) { tt.type(el, v); }
});

test("oz/mL toggle changes display only; cost and source stay put", () => {
  const t = boot();
  const before = t.$("#sDrinkCost").textContent;
  t.$('.seg [data-unit="ml"]').click();
  assert.equal(field(t, rows(t)[0], "amount").value, "60");
  assert.equal(field(t, rows(t)[3], "amount").value, "15");
  assert.equal(t.$("#sDrinkCost").textContent, before);
  assert.match(t.$('[data-out="tags"]', rows(t)[0]).textContent, /Entered as 2 oz/);
  for (let i = 0; i < 10; i++) { t.$('.seg [data-unit="floz"]').click(); t.$('.seg [data-unit="ml"]').click(); }
  assert.equal(t.S().draft.lines[0].amount, "2");
  assert.equal(t.S().draft.lines[0].amountUnit, "floz");
  // typing in mL makes mL the source
  t.type(field(t, rows(t)[0], "amount"), "45");
  assert.equal(t.S().draft.lines[0].amountUnit, "ml");
  assert.equal(costOf(t, rows(t)[0]), "$1.92"); // 45/750*32
  // pour chips
  t.$('[data-pour="30"]', rows(t)[0]).click();
  assert.equal(costOf(t, rows(t)[0]), "$1.28");
});

test("count and weight ingredients", () => {
  const t = boot();
  t.$("#clearExample").click();
  const r = rows(t)[0];
  t.type(field(t, r, "name"), "Lime");
  t.choose(field(t, r, "pkgPreset"), "custom");
  let row = rows(t)[0];
  t.type(field(t, row, "size"), "1");
  t.choose(field(t, row, "sizeUnit"), "each");
  row = rows(t)[0];
  t.type(field(t, row, "price"), "0.50");
  t.type(field(t, row, "amount"), "1/2");
  assert.equal(costOf(t, row), "$0.25");
  // weight: sugar 2 lb bag $3, 10 g
  t.$("#addRow").click();
  let r2 = rows(t)[1];
  t.choose(field(t, r2, "pkgPreset"), "custom");
  r2 = rows(t)[1];
  t.type(field(t, r2, "size"), "2");
  t.choose(field(t, r2, "sizeUnit"), "lb");
  r2 = rows(t)[1];
  assert.equal(field(t, r2, "amountUnit").value, "ozwt");
  t.choose(field(t, r2, "amountUnit"), "g");
  t.type(field(t, r2, "price"), "3");
  t.type(field(t, r2, "amount"), "10");
  assert.equal(costOf(t, r2), "$0.03");
  assert.equal(t.$('[data-pour]', r2), null); // no fluid pour chips for weight
});

test("invalid inputs show messages and are excluded, never NaN", () => {
  const t = boot();
  const r = rows(t)[0];
  t.type(field(t, r, "price"), "abc");
  assert.equal(costOf(t, r), "—");
  assert.equal(t.$('[data-out="err"]', r).hidden, false);
  assert.ok(r.classList.contains("has-error"));
  t.type(t.$("#targetPct"), "0");
  assert.equal(t.$("#targetErr").hidden, false);
  assert.equal(t.$("#sSuggested").textContent, "—");
  t.type(t.$("#menuPrice"), "0");
  assert.equal(t.$("#sBevPct").textContent, "—");
  t.type(field(t, r, "wastePct"), "100");
  assert.match(t.$('[data-out="err"]', r).textContent, /Waste/);
  assert.ok(!t.$("main").textContent.includes("NaN"));
});

test("waste and additional costs", () => {
  const t = boot();
  t.$("#clearExample").click();
  const r = rows(t)[0];
  t.type(field(t, r, "price"), "27"); t.type(field(t, r, "amount"), "1"); // 750 mL bottle, exact $1.0646
  t.$('.seg [data-unit="ml"]').click();
  t.type(field(t, rows(t)[0], "amount"), "25"); // 25/750*27 = 0.90
  assert.equal(t.$("#sDrinkCost").textContent, "$0.90");
  t.type(t.$("#recipeWaste"), "10");
  assert.equal(t.$("#sDrinkCost").textContent, "$1.00");
  t.type(field(t, rows(t)[0], "wastePct"), "0"); // row override
  assert.equal(t.$("#sDrinkCost").textContent, "$0.90");
  t.type(t.$('[data-extra="napkins"]'), "0.05");
  t.type(t.$('[data-extra="straws"]'), "0.05");
  assert.equal(t.$("#sDrinkCost").textContent, "$1.00");
  assert.match(t.$("#extrasSummary").textContent, /\$0\.10/);
});

test("scaling shows batch totals separately from per-drink", () => {
  const t = boot();
  t.$('[data-serv="100"]').click();
  assert.equal(t.$("#sDrinkCost").textContent, "$3.69");
  assert.match(t.$("#batchKv").textContent, /Ingredient cost for 100 drinks\$369\.32/);
  assert.match(t.$("#batchKv").textContent, /Revenue for 100 drinks\$1,400\.00/);
});

test("save, persist across reload, duplicate, delete with undo, search", async () => {
  let t = boot();
  t.$("#saveRecipe").click();
  assert.equal(t.$("#saveState").textContent, "Saved");
  t.type(t.$("#menuPrice"), "15");
  assert.equal(t.$("#saveState").textContent, "Unsaved changes");
  t.$("#saveRecipe").click();
  const stored = t.flush();
  t = boot(stored);
  assert.equal(t.$("#recipeName").value, "Classic Margarita");
  assert.equal(t.$("#menuPrice").value, "15");
  assert.equal(t.$("#saveState").textContent, "Saved");
  t.w.location.hash = "recipes"; t.w.dispatchEvent(new t.w.HashChangeEvent("hashchange"));
  assert.equal(t.$$("#recipeList .item").length, 1);
  assert.match(t.$("#recipeList .item").textContent, /\$3\.69/);
  t.$('#recipeList [data-ract="dup"]').click();
  assert.equal(t.$$("#recipeList .item").length, 2);
  t.type(t.$("#recipeSearch"), "copy");
  assert.equal(t.$$("#recipeList .item").length, 1);
  t.$('#recipeList [data-ract="del"]').click();
  assert.equal(t.$$("#recipeList .item").length, 0);
  t.$("#toastUndo").click();
  t.type(t.$("#recipeSearch"), "");
  assert.equal(t.$$("#recipeList .item").length, 2);
  // open the copy
  t.type(t.$("#recipeSearch"), "copy");
  t.$('#recipeList [data-ract="open"]').click();
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(t.$("#recipeName").value, "Classic Margarita (copy)");
  assert.equal(t.$("#view-calculator").hidden, false);
});

test("ingredient library: save from row, reuse, price updates flow through, overrides respected", () => {
  let t = boot();
  t.$("#clearExample").click();
  const r = rows(t)[0];
  t.type(field(t, r, "name"), "Tito’s Vodka"); t.type(field(t, r, "price"), "24.99");
  t.$('[data-act="save-lib"]', r).click();
  assert.equal(t.S().library.length, 1);
  assert.match(t.$('[data-out="tags"]', rows(t)[0]).textContent, /From My ingredients/);
  t.type(field(t, rows(t)[0], "amount"), "2");
  t.type(t.$("#recipeName"), "Vodka soda");
  t.$("#saveRecipe").click();
  // add the same bottle to a second line via picker
  t.$("#openPicker").click();
  assert.equal(t.$("#picker").hidden, false);
  t.$("#pickerList [data-pick]").click();
  assert.equal(rows(t).length, 2);
  assert.equal(t.d.activeElement, field(t, rows(t)[1], "amount"));
  t.type(field(t, rows(t)[1], "amount"), "1");
  t.type(field(t, rows(t)[1], "price"), "30"); // recipe-specific override on line 2
  assert.match(t.$('[data-out="tags"]', rows(t)[1]).textContent, /Custom price/);
  t.$("#saveRecipe").click();
  // change library price
  t.w.location.hash = "ingredients"; t.w.dispatchEvent(new t.w.HashChangeEvent("hashchange"));
  assert.match(t.$("#libList").textContent, /In 1 recipe/);
  t.type(t.$('#libList [data-lf="price"]'), "30");
  t.w.location.hash = "calculator"; t.w.dispatchEvent(new t.w.HashChangeEvent("hashchange"));
  assert.equal(field(t, rows(t)[0], "price").value, "30");
  assert.equal(costOf(t, rows(t)[0]), "$2.37"); // 2oz of $30/750
  assert.equal(t.S().draft.lines[1].price, "30"); // override kept
  t.type(field(t, rows(t)[1], "price"), "40");
  t.w.location.hash = "ingredients"; t.w.dispatchEvent(new t.w.HashChangeEvent("hashchange"));
  t.type(t.$('#libList [data-lf="price"]'), "20");
  t.w.location.hash = "calculator"; t.w.dispatchEvent(new t.w.HashChangeEvent("hashchange"));
  assert.equal(field(t, rows(t)[1], "price").value, "40"); // not silently overwritten
  t.$('[data-act="revert-price"]', rows(t)[1]).click();
  assert.equal(field(t, rows(t)[1], "price").value, "20");
  // saved recipe list reflects library price
  t.w.location.hash = "recipes"; t.w.dispatchEvent(new t.w.HashChangeEvent("hashchange"));
  // saved version has line1 linked ($20 -> 2oz = 1.58) + line2 override $30 1oz = 1.18
  assert.match(t.$("#recipeList").textContent, /\$2\.76/);
  // delete library item: recipes keep last values
  t.w.location.hash = "ingredients"; t.w.dispatchEvent(new t.w.HashChangeEvent("hashchange"));
  t.$("#libList [data-ldel]").click();
  assert.equal(t.S().library.length, 0);
  assert.equal(t.S().recipes[0].lines[0].price, "20");
  assert.equal(t.S().recipes[0].lines[0].libId, null);
  t.$("#toastUndo").click();
  assert.equal(t.S().library.length, 1);
  assert.deepEqual(t.errors, []);
});

test("add library item directly and 25-ingredient limit", () => {
  const t = boot();
  t.w.location.hash = "ingredients"; t.w.dispatchEvent(new t.w.HashChangeEvent("hashchange"));
  t.type(t.$('#libNew [data-lf="name"]'), "Campari");
  t.type(t.$('#libNew [data-lf="price"]'), "29.99");
  t.$("#libAdd").click();
  assert.equal(t.S().library.length, 1);
  t.w.location.hash = "calculator"; t.w.dispatchEvent(new t.w.HashChangeEvent("hashchange"));
  for (let i = 0; i < 30; i++) t.$("#addRow").click();
  assert.equal(rows(t).length, 25);
  assert.equal(t.$("#addRow").disabled, true);
  assert.equal(t.$("#limitNote").hidden, false);
});

test("export/import round trip and settings", async () => {
  const t = boot();
  t.$("#saveRecipe").click();
  const json = JSON.stringify({ app: "jigger", version: 1, library: [{ id: "x1", name: "Gin", price: "28", size: "1", sizeUnit: "l" }],
    recipes: [{ id: "r9", name: "Gimlet", lines: [{ id: "a", libId: "x1", amount: "2", amountUnit: "floz" }], menuPrice: "13" }] });
  const input = t.$("#importFile");
  const file = new t.w.File([json], "b.json", { type: "application/json" });
  Object.defineProperty(input, "files", { value: [file], configurable: true });
  input.dispatchEvent(new t.w.Event("change"));
  await new Promise((r) => setTimeout(r, 50));
  assert.equal(t.S().recipes.length, 2);
  assert.match(t.$("#toastMsg").textContent, /Imported 1 recipe and 1 ingredient/);
  t.w.location.hash = "recipes"; t.w.dispatchEvent(new t.w.HashChangeEvent("hashchange"));
  assert.match(t.$("#recipeList").textContent, /Gimlet\s*1 ingredient/);
  assert.match(t.$("#recipeList").textContent, /\$1\.66/); // 2oz (59.147mL) of $28/L
  // bad import
  Object.defineProperty(input, "files", { value: [new t.w.File(["nope"], "x.json")], configurable: true });
  input.dispatchEvent(new t.w.Event("change"));
  await new Promise((r) => setTimeout(r, 50));
  assert.match(t.$("#toastMsg").textContent, /isn’t a Jigger backup/);
  // currency
  t.w.location.hash = "preferences"; t.w.dispatchEvent(new t.w.HashChangeEvent("hashchange"));
  t.choose(t.$("#setCurrency"), "EUR");
  t.w.location.hash = "calculator"; t.w.dispatchEvent(new t.w.HashChangeEvent("hashchange"));
  assert.equal(t.$("#sDrinkCost").textContent, "€3.69");
  t.choose(t.$("#setTheme"), "light");
  assert.equal(t.d.documentElement.getAttribute("data-theme"), "light");
  assert.deepEqual(t.errors, []);
});
