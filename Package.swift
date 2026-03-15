// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "seshboard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "seshboard-cli", targets: ["seshboard-cli"]),
        .library(name: "SeshboardCore", targets: ["SeshboardCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.4.1"),
    ],
    targets: [
        .target(
            name: "SeshboardCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "seshboard-cli",
            dependencies: [
                "SeshboardCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SeshboardCoreTests",
            dependencies: ["SeshboardCore"]
        ),
    ]
)
