# Jigger for iPhone and iPad

Jigger is a bar and cocktail drink cost calculator. A working web version already exists; this repo turns it into a native SwiftUI app for iPhone and iPad, published on the App Store.

## App identity

- App Store name: **Jigger Cost**
- Home-screen display name (`CFBundleDisplayName`): **Jigger**
- Bundle ID: **com.chadjara.jigger** (already registered; the App Store Connect app record uses it)
- SKU: jigger-ios

## The owner has no Mac

The owner cannot install Xcode or any developer tools. Every build, test, signing step and TestFlight upload must run in **GitHub Actions on GitHub-hosted macOS runners**. Never ask the owner to run commands locally or open Xcode.

- Project must build with the Xcode version available on the `macos-latest` runner; select it explicitly in the workflow.
- Deployment target: iOS 17.0 (SwiftData requires it). Universal app: iPhone and iPad.
- Signing: automatic, cloud-managed, using an App Store Connect API key. There are no local certificates.
- Secrets available to workflows: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (full text of the .p8 key). Never print them in logs and never commit key material.

## Reference material (`reference/`)

- `engine.js`: the web calculation engine. It is the source of truth for every formula.
- `engine.test.js`: its tests. Port **every** case to Swift with identical inputs and expected values so the app matches the website to the cent.
- `jigger.html`: the complete web app (features, layout, copy, design).
- `ui.test.js`: the web integration tests, describing expected app behavior.

## Non-negotiables

- Money math uses Foundation `Decimal`. Multiply before dividing; round only for display (2 places, half-up).
- Cost uses exact unit factors (1 fl oz = 29.5735295625 mL). The oz/mL toggle only changes display, using the bar convention 1 oz = 30 mL, and never alters what the user entered.
- Fluid ounces and ounces by weight are distinct units.
- Waste is a yield loss: cost / (1 - waste%). A line's own waste % overrides the recipe-wide waste %.
- Suggested price = drink cost / target %. Beverage cost % = cost / price x 100. Gross margin = (price - cost) / price x 100. Never divide by zero; invalid input shows a message, never NaN or a crash.
- Max 25 ingredients per recipe.
- Library prices flow into recipes by reference, but a recipe's custom price override is never silently overwritten.
- Figures cover ingredients and listed additional costs only, never labor, rent, taxes or overhead.
- Keep it simple: a fast, beautiful calculator, not an inventory system. Dark charcoal with warm brass/gold accents, matching the web version.

## Features

Live calculator, oz/mL toggle, pour and bottle-size presets, count and weight ingredients, additional costs (collapsed), suggested price from target %, menu price analysis, batch scaling (1/10/25/100), saved recipes (search, duplicate, delete with undo), My Ingredients library, JSON export/import, currency setting, Classic Margarita example with clearly illustrative prices.

**Print / share cost analysis PDF** (AirPrint, Save to Files, Share): ingredient table with each ingredient's share of cost, biggest cost driver, additional costs and waste assumptions, target %, suggested price, menu price, beverage cost %, gross profit and margin, a price ladder at 18/20/22/25% beverage cost, batch totals, date and currency, and a note that overhead is excluded.

Layout: iPad uses a sidebar with calculator and summary side by side; iPhone uses tabs.

## CI expectations

- Every pull request: build and run all unit and UI tests on an iOS simulator.
- Merges to `main`: archive, sign and upload to TestFlight.
- Cache dependencies; skip builds for documentation-only changes. macOS minutes are limited on a private repo.
- A task is not done until the GitHub Actions checks pass.
