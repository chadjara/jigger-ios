# Jigger for iPhone and iPad

Jigger (App Store name **Jigger Cost**) is a fast bar and cocktail drink cost calculator. It is a native SwiftUI app for iPhone and iPad, ported from the Jigger website, and it matches the website's figures to the cent.

It works fully offline. There is no backend, no accounts, no ads, no analytics and no tracking. Data stays on the device unless the user exports a backup or shares a cost sheet.

## What it does

- **Live calculator:** price paid, package (presets from 50 mL to 1.75 L, or any size and unit), amount per drink, and a cost per line with its share of the total.
- **oz/mL toggle:** display only, using the bar convention 1 oz = 30 mL. Cost always uses exact unit factors and what you typed.
- **Count and weight ingredients:** limes each, sugar by g, oz wt, kg or lb. Fluid ounces and ounces by weight are separate units.
- **Waste:** treated as a yield loss, per recipe or per ingredient. **Additional costs:** garnish, napkin, straw, cup, other.
- **Pricing:** suggested price from a target beverage cost %, plus menu-price analysis (beverage cost %, gross profit, gross margin).
- **Batch scaling:** 1, 10, 25, 100 or any number of drinks.
- **Saved recipes:** search, duplicate, and delete with undo.
- **My Ingredients:** prices flow into recipes by reference, and a recipe's custom price is never overwritten.
- **Cost analysis PDF:** print with AirPrint, Save to Files, or Share.
- **Backup:** JSON export and import, compatible with the website's backups.
- **Settings:** currency and appearance (dark charcoal and brass by default; also light or match the device).
- **Layout:** iPad uses a sidebar with the calculator and summary side by side. iPhone uses tabs, with a pinned cost bar.

## Project layout

```
Packages/JiggerKit/          Swift package, no UI, no third-party dependencies
  Sources/JiggerEngine/      calculation engine: a line-by-line port of reference/engine.js (Foundation Decimal)
  Sources/JiggerCore/        app state and every user action, JSON persistence, backup import/export, cost-sheet HTML
  Tests/                     every case from reference/engine.test.js and the reference/ui.test.js scenarios
Jigger/                      SwiftUI app: design tokens and components, feature views, PDF/print/share, assets
JiggerTests/                 app-target tests (PDF rendering, theme, backup document)
JiggerUITests/               XCUITest end-to-end flows on iPhone and iPad
project.yml                  XcodeGen spec; CI generates Jigger.xcodeproj from it
reference/                   the website's engine, tests and app (the source of truth for formulas)
```

Views contain no arithmetic. They call `AppStore` methods and show engine results, so every formula and behaviour is tested without a UI.

## Continuous integration

Everything builds in GitHub Actions; no Mac is needed.

| Workflow | When | What |
| --- | --- | --- |
| `CI` | every pull request | `swift test` of JiggerKit on Linux (fast), then generate the project and build it for an iPhone simulator. **Draft PRs** run only the app unit tests on the simulator (about 3 macOS minutes). **Ready-for-review PRs** run every unit, engine, core and UI test on iPhone, plus the iPad layout test |
| `TestFlight` | every merge to `main` | archive a signed Release build and upload it to TestFlight; the build number is the workflow's run number (3, 4, 5…) |
| `Screenshots` | run by hand (Actions → Screenshots → Run workflow) | capture App Store screenshots with demo recipes on the 6.9" iPhone and 13" iPad simulators; download them from the `app-store-screenshots` artifact |

`CI` and `TestFlight` skip changes that only touch documentation or `reference/`. A new push cancels the CI run it replaces. macOS minutes count 10× against a private repo's Actions allowance, so keep PRs as drafts while iterating and mark them ready once, for the full run before merging.

### Version numbers

Two numbers identify every upload: the **version** (`MARKETING_VERSION` in `project.yml`) and the **build number** (the `TestFlight` workflow's run number, set automatically). TestFlight shows them as "1.0.0 (4)".

- **Before the App Store launch:** the version stays **1.0.0**. Each TestFlight upload is a new build of 1.0.0 (builds 4, 5, 6, …), and the first App Store release ships as 1.0.0.
- **After launch** (semantic versioning): 1.0.1 for fixes, 1.1.0 for new features, 2.0.0 for a major overhaul. Change `MARKETING_VERSION` in the PR that starts the release; the build number keeps counting up on its own.

### Signing setup (one time)

- Repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_P8` (the full text of the .p8 file).
- The App Store Connect API key needs the **Admin** role, or **App Manager** with access to cloud-managed certificates. Xcode uses it to create the distribution certificate and profile in the cloud.
- The workflow finds your Team ID through the API. If that lookup ever fails, add a repository **variable** named `APPLE_TEAM_ID` holding the 10-character Team ID from developer.apple.com → Account → Membership.

## App Store submission

`docs/app-store/listing.md` has the App Store text, ready to paste: name, subtitle, description, keywords, categories, privacy answers, age rating and review notes. `docs/app-store/privacy-policy.md` is the privacy policy to publish (the Privacy Policy URL is required).

## Installing a build

After a merge to `main` finishes the `TestFlight` workflow, the build appears in App Store Connect → Jigger Cost → TestFlight within a few minutes, once Apple has processed it. Add yourself as an internal tester, then install the TestFlight app on your iPhone or iPad.
