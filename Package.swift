// swift-tools-version: 5.9

// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import PackageDescription

let package = Package(
    name: "Keystarter",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Keystarter",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Keystarter",
            resources: [
                .copy("../../Resources/Compiled/Keystarter.icns"),
                .process("../../Resources/MenuBar")
            ]
        )
    ]
)
