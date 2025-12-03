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
            targets: ["GoSTL"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "GoSTL",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "GoSTL",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GoSTLTests",
            dependencies: ["GoSTL"]
        ),
    ]
)
