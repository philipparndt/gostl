import Foundation

/// This module's resource bundle, looked for rather than assumed.
///
/// SwiftPM generates a `Bundle.module` accessor for a target with resources, and
/// the one `swift build` generates is not usable by a library:
///
/// - It looks in exactly two places: beside `Bundle.main.bundleURL`, which for
///   an `.app` is the bundle's *root*, and the absolute `.build` path of the
///   machine that compiled it.
/// - When neither holds the bundle it calls `fatalError`.
///
/// GoSTL.app gets away with it because its release copies the bundle to the app
/// root. A host that puts it where resources belong — `Contents/Resources` — does
/// not: on the machine that built the host, the `.build` path is still there and
/// hides the problem; on any other machine the first 3D view takes the whole
/// host process down (Abydos 0.23.1, opening an STL pane).
///
/// So nothing here reaches for `Bundle.module`. This returns `nil` where the
/// accessor would abort, and a missing shader is a thrown error the host can
/// show, not a crash.
enum ResourceBundle {
    /// SwiftPM's name for this target's bundle: `<package>_<target>`.
    static let name = "GoSTL_GoSTL"

    /// Anchor for asking which bundle this code was loaded from.
    private final class Anchor {}

    /// Directories the bundle may sit in, in the order they are tried.
    static var searchDirectories: [URL] {
        var candidates: [URL] = []

        // The override SwiftPM's own accessor honours in a debug build.
        if let path = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] {
            candidates.append(URL(fileURLWithPath: path))
        }

        // An app that hosts the library, with its resources where they belong.
        if let resources = Bundle.main.resourceURL { candidates.append(resources) }
        // GoSTL.app as released, and a bare executable with the bundle beside it.
        candidates.append(Bundle.main.bundleURL)
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent())
        }

        // A framework or a test bundle this code was linked into.
        let own = Bundle(for: Anchor.self)
        if let resources = own.resourceURL { candidates.append(resources) }
        candidates.append(own.bundleURL.deletingLastPathComponent())

        return candidates
    }

    /// The bundle, or `nil` when this build has none.
    static let bundle: Bundle? = locate(in: searchDirectories)

    /// A bundle of this name in the first of these directories that has one.
    static func locate(_ name: String = name, in directories: [URL]) -> Bundle? {
        for base in directories {
            let url = base.appendingPathComponent("\(name).bundle", isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }

    /// A resource of this module, or `nil`.
    static func url(forResource name: String?, withExtension extension: String?) -> URL? {
        bundle?.url(forResource: name, withExtension: `extension`)
    }
}
