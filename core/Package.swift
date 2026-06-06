// swift-tools-version:6.2
//
// Package manifest for GalleyCore — the headless, UI-free domain core of Galley
// (overview §13, step 1). No AppKit / SwiftUI / NSAttributedString
// belongs here; the macOS shell consumes this package later (ADR-0001, ADR-0002).
// Public products: the `GalleyCore` library.

import PackageDescription

let package = Package(
    name: "GalleyCore",
    products: [
        .library(name: "GalleyCore", targets: ["GalleyCore"]),
    ],
    targets: [
        .target(name: "GalleyCore"),
        .testTarget(name: "GalleyCoreTests", dependencies: ["GalleyCore"]),
    ]
)
