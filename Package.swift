// swift-tools-version: 6.0
import PackageDescription

// The manifest lives at the repository root while the Swift sources stay one
// directory down, in GoSTL-Swift/.
//
// SwiftPM only finds a Package.swift at the root of a repository, so a manifest
// in a subdirectory can be reached solely by a path dependency — and a path
// dependency records nothing in the depending project's Package.resolved, so
// nobody can say afterwards which version of this package a build contained.
// Moving the manifest up rather than the sources down keeps every source path
// in git history where it was; the cost is the explicit `path:` on each target
// below, which must name the subdirectory.
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
            path: "GoSTL-Swift/GoSTL",
            resources: [
                // Relative to the target's own path, so this still names
                // GoSTL-Swift/GoSTL/Resources.
                .process("Resources")
            ]
        ),
        // Only an entry point; everything else is in the library.
        .executableTarget(
            name: "GoSTLMain",
            dependencies: ["GoSTL"],
            path: "GoSTL-Swift/GoSTLMain"
        ),
        .testTarget(
            name: "GoSTLTests",
            dependencies: ["GoSTL"],
            // Named rather than left to the default: SwiftPM would look for
            // Tests/GoSTLTests beside the manifest, which is now the root.
            path: "GoSTL-Swift/Tests/GoSTLTests"
        ),
    ]
)
