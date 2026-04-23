// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "seshctl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "seshctl-cli", targets: ["seshctl-cli"]),
        .executable(name: "SeshctlApp", targets: ["SeshctlApp"]),
        .library(name: "SeshctlCore", targets: ["SeshctlCore"]),
        .library(name: "SeshctlUI", targets: ["SeshctlUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.4.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
    ],
    targets: [
        .target(
            name: "SeshctlCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "SeshctlUI",
            dependencies: [
                "SeshctlCore",
            ]
        ),
        .executableTarget(
            name: "SeshctlApp",
            dependencies: [
                "SeshctlCore",
                "SeshctlUI",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .executableTarget(
            name: "seshctl-cli",
            dependencies: [
                "SeshctlCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SeshctlCoreTests",
            dependencies: ["SeshctlCore"]
        ),
        .testTarget(
            name: "SeshctlUITests",
            dependencies: ["SeshctlUI", "SeshctlCore"]
        ),
        .testTarget(
            name: "SeshctlAppTests",
            dependencies: ["SeshctlApp"]
        ),
    ]
)
