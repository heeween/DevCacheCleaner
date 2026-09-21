// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DevCacheCleaner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DevCacheCore",
            targets: ["DevCacheCore"]
        ),
        .executable(
            name: "devcache",
            targets: ["DevCacheCLI"]
        ),
        .executable(
            name: "DevCacheCleanerApp",
            targets: ["DevCacheApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "DevCacheCore",
            path: "Sources/DevCacheCore"
        ),
        .executableTarget(
            name: "DevCacheCLI",
            dependencies: [
                "DevCacheCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/DevCacheCLI"
        ),
        .executableTarget(
            name: "DevCacheApp",
            dependencies: [
                "DevCacheCore"
            ],
            path: "Sources/DevCacheApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DevCacheCoreTests",
            dependencies: ["DevCacheCore"],
            path: "tests"
        ),
    ]
)
