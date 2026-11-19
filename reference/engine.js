/* Jigger calculation engine — pure functions, no DOM.
 * All money math uses Decimal (decimal.js). Nothing is rounded until display.
 * Inputs are the raw strings people type; parsing happens here so the UI never
 * does arithmetic of its own.
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory(require("decimal.js"));
  else root.JiggerEngine = factory(root.Decimal);
})(typeof self !== "undefined" ? self : this, function (Decimal) {
  "use strict";
  const D = Decimal.clone({ precision: 40, rounding: Decimal.ROUND_HALF_UP });
  const ZERO = new D(0), HUNDRED = new D(100);

  /* Units. Base units: mL for volume, g for weight, "each" for count.
   * Exact factors are used for cost so a pour costs exactly what was entered. */
  const UNITS = {
    ml:   { dim: "volume", factor: "1",            label: "mL" },
    l:    { dim: "volume", factor: "1000",         label: "L" },
    floz: { dim: "volume", factor: "29.5735295625", label: "fl oz" },
    g:    { dim: "weight", factor: "1",            label: "g" },
    kg:   { dim: "weight", factor: "1000",         label: "kg" },
    ozwt: { dim: "weight", factor: "28.349523125", label: "oz wt" },
    lb:   { dim: "weight", factor: "453.59237",    label: "lb" },
    each: { dim: "count",  factor: "1",            label: "each" },
  };
  const USE_UNITS = {
    volume: ["floz", "ml"],
    weight: ["g", "ozwt", "kg", "lb"],
    count:  ["each"],
  };
  /* Bar convention used ONLY to show a pour in the other unit (1 oz ≈ 30 mL). */
  const BAR_ML_PER_OZ = new D(30);

  function dimOf(unit) { return UNITS[unit] ? UNITS[unit].dim : null; }

  /* Parse a typed number. Accepts "24.99", "$24.99", "1,000", ".5", "1/2", "1 1/2".
   * Returns Decimal, or null for blank, or NaN-marker {invalid:true}. */
  function parse(input) {
    if (input === null || input === undefined) return null;
    if (typeof input === "number") return Number.isFinite(input) ? new D(input) : INVALID;
    let s = String(input).trim().replace(/[$€£¥\s]+$/g, "").replace(/^[$€£¥]/, "").replace(/,/g, "").trim();
    if (s === "") return null;
    let m = s.match(/^(\d+)\s+(\d+)\/(\d+)$/);
    if (m) return +m[3] === 0 ? INVALID : new D(m[1]).plus(new D(m[2]).div(m[3]));
    m = s.match(/^(\d*\.?\d+)\/(\d*\.?\d+)$/);
    if (m) return new D(m[2]).isZero() ? INVALID : new D(m[1]).div(m[2]);
    if (!/^-?(\d+\.?\d*|\.\d+)$/.test(s)) return INVALID;
    return new D(s);
  }
  const INVALID = { invalid: true };
  const isInvalid = (v) => v === INVALID;

  function toBase(value, unit) {
    const u = UNITS[unit];
    if (!u) throw new Error("Unknown unit " + unit);
    return new D(value).times(u.factor);
  }

  /* Waste is a yield loss: 10% waste means only 90% of each bottle reaches a glass,
   * so every pour costs price-per-unit ÷ 0.90. */
  function applyWaste(cost, wastePct) {
    if (!wastePct || wastePct.isZero()) return cost;
    return cost.div(HUNDRED.minus(wastePct).div(HUNDRED));
  }

  /* Cost of one ingredient line.
   * line: { price, size, sizeUnit, amount, amountUnit, wastePct } (strings as typed)
   * fallbackWaste: recipe-wide waste % string used when the line has none.
   * Returns { status: "ok"|"incomplete"|"invalid", cost: Decimal|null, errors: {field: msg} } */
  function lineCost(line, fallbackWaste) {
    const errors = {};
    const price = parse(line.price), size = parse(line.size), amount = parse(line.amount);
    let waste = parse(line.wastePct);
    if (waste === null) waste = parse(fallbackWaste);

    if (isInvalid(price)) errors.price = "Enter a price like 24.99";
    else if (price && price.isNeg()) errors.price = "Price can’t be negative";
    if (isInvalid(size)) errors.size = "Enter a size like 750";
    else if (size && !size.gt(0)) errors.size = "Size must be more than 0";
    if (isInvalid(amount)) errors.amount = "Enter an amount like 1.5 or 1/2";
    else if (amount && amount.isNeg()) errors.amount = "Amount can’t be negative";
    if (isInvalid(waste)) errors.waste = "Enter a waste % like 5";
    else if (waste && (waste.isNeg() || waste.gte(100))) errors.waste = "Waste must be 0–99%";
    const sd = dimOf(line.sizeUnit), ad = dimOf(line.amountUnit);
    if (!sd) errors.size = errors.size || "Choose a package unit";
    if (!ad) errors.amount = errors.amount || "Choose a unit";
    if (sd && ad && sd !== ad) errors.amount = `Package is sold by ${sd}; measure the pour by ${sd} too`;

    if (Object.keys(errors).length) return { status: "invalid", cost: null, errors };
    if (price === null || size === null || amount === null) return { status: "incomplete", cost: null, errors };

    // Multiply first, divide last: keeps results exact whenever they can be.
    const raw = price.times(toBase(amount, line.amountUnit)).div(toBase(size, line.sizeUnit));
    return { status: "ok", cost: applyWaste(raw, waste || ZERO), errors };
  }

  /* Full recipe totals. All results are Decimal or null when they can’t be computed. */
  function recipeTotals(recipe) {
    const lines = (recipe.lines || []).map((l) => ({ id: l.id, ...lineCost(l, recipe.wastePct) }));
    let ingredientCost = ZERO, counted = 0, incomplete = 0, invalid = 0;
    for (const l of lines) {
      if (l.status === "ok") { ingredientCost = ingredientCost.plus(l.cost); counted++; }
      else if (l.status === "incomplete") incomplete++;
      else invalid++;
    }
    const extrasErrors = {};
    let extrasCost = ZERO;
    for (const [k, v] of Object.entries(recipe.extras || {})) {
      const p = parse(v);
      if (isInvalid(p) || (p && p.isNeg())) { extrasErrors[k] = "Enter an amount like 0.10"; continue; }
      if (p) extrasCost = extrasCost.plus(p);
    }
    const drinkCost = ingredientCost.plus(extrasCost);
    const hasCost = counted > 0 || extrasCost.gt(0);

    const target = parse(recipe.targetPct);
    let targetError = null, suggestedPrice = null;
    if (isInvalid(target)) targetError = "Enter a percentage like 20";
    else if (target !== null && (!target.gt(0) || target.gt(100))) targetError = "Target must be between 0 and 100%";
    else if (target !== null && hasCost) suggestedPrice = drinkCost.div(target.div(HUNDRED));

    const menu = parse(recipe.menuPrice);
    let menuError = null, bevCostPct = null, grossProfit = null, grossMargin = null;
    if (isInvalid(menu)) menuError = "Enter a price like 14.00";
    else if (menu !== null && !menu.gt(0)) menuError = "Menu price must be more than 0";
    else if (menu !== null && hasCost) {
      bevCostPct = drinkCost.div(menu).times(HUNDRED);
      grossProfit = menu.minus(drinkCost);
      grossMargin = grossProfit.div(menu).times(HUNDRED);
    }

    let servings = parse(recipe.servings);
    let servingsError = null;
    if (servings === null) servings = new D(1);
    else if (isInvalid(servings) || !servings.gt(0)) { servingsError = "Servings must be more than 0"; servings = new D(1); }
    const batchCost = drinkCost.times(servings);
    const batchRevenue = menu && !isInvalid(menu) && menu.gt(0) ? menu.times(servings) : null;

    const shares = {};
    for (const l of lines) if (l.status === "ok" && drinkCost.gt(0)) shares[l.id] = l.cost.div(drinkCost).times(HUNDRED);

    return {
      lines, shares, ingredientCost, extrasCost, drinkCost, hasCost,
      counted, incomplete, invalid, extrasErrors,
      suggestedPrice, targetError, bevCostPct, grossProfit, grossMargin, menuError,
      servings, servingsError, batchCost, batchRevenue,
      batchProfit: batchRevenue ? batchRevenue.minus(batchCost) : null,
    };
  }

  /* Display helpers — rounding happens only here. */
  function roundMoney(d) { return d === null ? null : d.toDecimalPlaces(2, Decimal.ROUND_HALF_UP); }
  function formatMoney(d, currency, locale) {
    if (d === null || d === undefined) return "—";
    const r = roundMoney(d);
    return new Intl.NumberFormat(locale || "en-US", { style: "currency", currency: currency || "USD",
      minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(r.toFixed(2)));
  }
  function formatPct(d, places = 1) {
    if (d === null || d === undefined) return "—";
    return d.toDecimalPlaces(places, Decimal.ROUND_HALF_UP).toFixed(places) + "%";
  }

  /* Show a volume pour in the other display unit using bar convention.
   * Converts from the SOURCE value each time, so toggling never drifts. */
  function displayPour(value, fromUnit, toUnit) {
    const v = parse(value);
    if (v === null || isInvalid(v)) return value;
    if (fromUnit === toUnit) return value;
    let out;
    if (fromUnit === "floz" && toUnit === "ml") out = v.times(BAR_ML_PER_OZ).toDecimalPlaces(1);
    else if (fromUnit === "ml" && toUnit === "floz") out = v.div(BAR_ML_PER_OZ).toDecimalPlaces(2);
    else return value;
    return out.toString();
  }

  return { D, UNITS, USE_UNITS, dimOf, parse, isInvalid, toBase, lineCost, recipeTotals,
    roundMoney, formatMoney, formatPct, displayPour, BAR_ML_PER_OZ };
});
