// swift-tools-version:6.2
//
// Package manifest for UntitledCore — the headless, UI-free domain core of
// Untitled (overview §13, step 1). No AppKit / SwiftUI / NSAttributedString
// belongs here; the macOS shell consumes this package later (ADR-0001, ADR-0002).
// Public products: the `UntitledCore` library.

import PackageDescription

let package = Package(
    name: "UntitledCore",
    products: [
        .library(name: "UntitledCore", targets: ["UntitledCore"]),
    ],
    targets: [
        .target(name: "UntitledCore"),
        .testTarget(name: "UntitledCoreTests", dependencies: ["UntitledCore"]),
    ]
)
