// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import Foundation
import PackageDescription

// Sparkle normally arrives as a remote binary artifact. On machines where
// SwiftPM's downloader can't reach GitHub, run scripts/fetch-sparkle.sh and
// build with MOTHBALL_LOCAL_SPARKLE=1 to use the vendored copy instead.
let useLocalSparkle = ProcessInfo.processInfo.environment["MOTHBALL_LOCAL_SPARKLE"] == "1"

let package = Package(
    name: "Mothball",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .executable(name: "mothball", targets: ["cli"]),
        .executable(name: "MothballApp", targets: ["MothballApp"]),
    ],
    dependencies: [
        // Test-only. Explicit dependency so `swift test` works on machines with
        // Command Line Tools but no full Xcode (whose SDK lacks Testing/XCTest).
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0"),
    ] + (useLocalSparkle ? [] : [
        // Approved third-party dependency (SPEC §3): app updates.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ]),
    targets: [
        .target(
            name: "Core",
            path: "Sources/Core",
            exclude: ["Localizable.xcstrings"],
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj"),
                // .copy preserves the rules/ directory layout inside the bundle.
                .copy("Resources/rules"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "cli",
            dependencies: ["Core"],
            path: "Sources/cli",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "MothballApp",
            dependencies: [
                "Core",
                useLocalSparkle ? "Sparkle" : .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "App",
            // AppIcon.icns ships at the bundle root via scripts/release.sh,
            // not through SwiftPM resource processing.
            exclude: ["Info.plist", "Localizable.xcstrings", "AppIcon.icns"],
            sources: ["Sources"],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ] + (useLocalSparkle ? [
        .binaryTarget(name: "Sparkle", path: "Vendor/Sparkle.xcframework"),
    ] : []) + [
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "Core",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/CoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
