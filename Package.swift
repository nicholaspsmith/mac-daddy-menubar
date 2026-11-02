// swift-tools-version:5.9
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import PackageDescription

let package = Package(
    name: "MacDaddy",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../StatusItemKit"),
        .package(path: "../HotkeyKit"),
    ],
    targets: [
        .target(name: "MacDaddyCore"),
        // The launcher (⌘Space: apps, math, conversions, emoji), formerly Menu Crane.
        .target(name: "LauncherCore", dependencies: [.product(name: "HotkeyKit", package: "HotkeyKit")]),
        .executableTarget(
            name: "MacDaddy",
            dependencies: [
                "MacDaddyCore", "LauncherCore",
                .product(name: "StatusItemKit", package: "StatusItemKit"),
                .product(name: "HotkeyKit", package: "HotkeyKit"),
            ],
            path: "Sources/MacDaddy"
        ),
        .testTarget(name: "MacDaddyCoreTests", dependencies: ["MacDaddyCore"]),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"]),
    ]
)
