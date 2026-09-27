import Foundation

/// This module's resource bundle, looked for rather than assumed.
///
/// SwiftPM generates a `Bundle.module` accessor for the target, and it is not
/// usable from a library another app embeds. It tries exactly two places:
///
/// - `Bundle.main.bundleURL/GoSTL_GoSTL.bundle` — for an `.app` that is the
///   bundle's *root*, beside `Contents`, which is where the Homebrew install
///   puts it and where a signed app cannot: codesign refuses unsealed contents
///   in the bundle root, so a host app carries it in `Contents/Resources`.
/// - the absolute `.build` path of whoever compiled it, baked into the binary.
///
/// Neither found, it calls `fatalError`. So an app that embeds this viewer
/// works on the machine that built it — where the second path still exists —
/// and dies on every other machine the first time a model is shown:
///
///     closure #1 in variable initialization expression of static NSBundle.module
///     specialized static MetalRenderer.loadShaderLibrary(device:)
///
/// Nobody who builds the host ever sees it, which is how it shipped.
///
/// So: never `Bundle.module`, always this. It returns `nil` where the generated
/// accessor would abort, and every caller already handles a resource that is
/// not there.
enum ResourceBundle {
    /// SwiftPM's name for this target's bundle: `<package>_<target>`.
    static let name = "GoSTL_GoSTL"

    /// Anchor for asking which bundle this code was loaded from, which is what
    /// makes the lookup work under `swift test` as well as in an app.
    private final class Anchor {}

    /// Directories the bundle may sit in, in the order they are tried.
    ///
    /// Each context puts it somewhere else — an embedding `.app` in
    /// `Contents/Resources`, the Homebrew `GoSTL.app` at its root, a bare
    /// `swift build` executable beside itself, a test run beside the test
    /// bundle — so rather than branch on which one this is, try each and take
    /// the first that holds it.
    static let searchDirectories: [URL] = {
        var candidates: [URL] = []

        // The override SwiftPM documents for its accessor on other platforms,
        // so a build that puts the bundle somewhere unusual can say where.
        if let path = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] {
            candidates.append(URL(fileURLWithPath: path))
        }

        if let resources = Bundle.main.resourceURL { candidates.append(resources) }
        candidates.append(Bundle.main.bundleURL)

        let own = Bundle(for: Anchor.self)
        if let resources = own.resourceURL { candidates.append(resources) }
        // SwiftPM places the bundle beside the test bundle, one level up.
        candidates.append(own.bundleURL.deletingLastPathComponent())

        // The application this executable ships inside, when it is not the
        // app's own binary — a tool in `Contents/Resources/bin/` has that
        // directory as its `Bundle.main`.
        if let resources = applicationResources(containing: Bundle.main.bundleURL) {
            candidates.append(resources)
        }

        return candidates
    }()

    /// The bundle, or `nil` when this build has none.
    static let bundle: Bundle? = locate(in: searchDirectories)

    /// A resource of this module, or `nil`.
    static func url(forResource name: String?, withExtension ext: String?) -> URL? {
        bundle?.url(forResource: name, withExtension: ext)
    }

    /// The named bundle in the first of these directories that has one.
    static func locate(_ name: String = name, in directories: [URL]) -> Bundle? {
        for base in directories {
            let url = base.appendingPathComponent("\(name).bundle", isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }

    /// The `Resources` directory of the `.app` a path is inside, if any.
    static func applicationResources(containing path: URL) -> URL? {
        var directory = path.resolvingSymlinksInPath()
        // Bounded, so a loop that trusts `deletingLastPathComponent` to reach
        // the end of a path cannot spin on `/`.
        for _ in 0..<8 {
            if directory.pathExtension == "app" {
                return directory
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
        return nil
    }
}
