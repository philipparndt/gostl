// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoSTL",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "GoSTL",
            targets: ["GoSTLMain"]
        ),
        // The viewer as a library, so another app can host it in a window of
        // its own rather than launching a second application.
        .library(
            name: "GoSTLKit",
            targets: ["GoSTL"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "GoSTL",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "GoSTL",
            resources: [
                .process("Resources")
            ]
        ),
        // Only an entry point; everything else is in the library.
        .executableTarget(
            name: "GoSTLMain",
            dependencies: ["GoSTL"],
            path: "GoSTLMain"
        ),
        .testTarget(
            name: "GoSTLTests",
            dependencies: ["GoSTL"]
        ),
    ]
)
