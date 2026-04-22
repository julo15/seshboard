// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeAICookieSpike",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "CookieSpike", path: "Sources/CookieSpike"),
    ]
)
