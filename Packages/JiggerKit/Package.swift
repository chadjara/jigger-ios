// swift-tools-version:5.10
// JiggerKit: everything in Jigger that is not UI.
//  - JiggerEngine: the calculation engine (a port of reference/engine.js). Pure functions, Foundation only.
//  - JiggerCore: app state, persistence, backup import/export and the cost-sheet builder.
// Both build and test on Linux and on Apple platforms, with no third-party dependencies.
import PackageDescription

let package = Package(
    name: "JiggerKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JiggerEngine", targets: ["JiggerEngine"]),
        .library(name: "JiggerCore", targets: ["JiggerCore"]),
    ],
    targets: [
        .target(name: "JiggerEngine"),
        .target(name: "JiggerCore", dependencies: ["JiggerEngine"]),
        .testTarget(name: "JiggerEngineTests", dependencies: ["JiggerEngine"]),
        .testTarget(name: "JiggerCoreTests", dependencies: ["JiggerCore"]),
    ]
)
