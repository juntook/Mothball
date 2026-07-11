// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

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
    ],
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
            dependencies: ["Core"],
            path: "App",
            exclude: ["Info.plist", "Localizable.xcstrings"],
            sources: ["Sources"],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
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
