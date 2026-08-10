import XCTest
@testable import GoSTL

/// The seam that says how OpenSCAD is run.
///
/// `findOpenSCADExecutable` answered with a path and every caller built a
/// `Process` around it, which can only ever mean a binary on this machine. What
/// is checked here is the two things an embedder supplying its own command has
/// to be able to rely on: that its command is used at all, and that it is told
/// which directory to run in — per call, not once, because relative
/// `include <…>` and `use <…>` resolve against it and the renderer uses a
/// different directory for different passes.
///
/// Nothing here runs OpenSCAD. The recorded command hands back `/usr/bin/true`,
/// which succeeds and writes nothing, so the renderer walks its own path
/// without anything having to be installed.
final class OpenSCADCommandTests: XCTestCase {
    private final class Recording: OpenSCADCommand, @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [(arguments: [String], workingDirectory: URL)] = []

        var recorded: [(arguments: [String], workingDirectory: URL)] {
            lock.lock(); defer { lock.unlock() }; return calls
        }

        func makeProcess(arguments: [String], workingDirectory: URL) throws -> Process {
            lock.lock()
            calls.append((arguments, workingDirectory))
            lock.unlock()

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
            process.arguments = []
            process.currentDirectoryURL = workingDirectory
            return process
        }
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gostl-openscad-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testTheEmbeddersCommandIsUsedInsteadOfLookingForAnInstalledCopy() throws {
        let workDir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let source = workDir.appendingPathComponent("part.scad")
        try Data("cube(10);\n".utf8).write(to: source)

        let command = Recording()
        let renderer = OpenSCADRenderer(workDir: workDir, openSCAD: command)
        _ = try renderer.renderToSTL(
            scadFile: source, outputFile: workDir.appendingPathComponent("out.stl")
        )

        let calls = command.recorded
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.arguments.first, "-o")
        XCTAssertEqual(calls.first?.arguments.last, source.path)
        XCTAssertEqual(calls.first?.workingDirectory.standardizedFileURL.path, workDir.path)
    }

    func testTheWorkingDirectoryIsGivenPerCallAndIsNotAlwaysTheSame() throws {
        // The export path is the one that changes it: the CSG passes run from
        // the directory the model is in, so that a model including the file
        // beside it resolves, while the render itself runs from the scratch
        // directory. A command that fixed one directory for the whole session
        // would work here and fail on somebody's project.
        let workDir = try makeDirectory()
        let sourceDir = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: workDir)
            try? FileManager.default.removeItem(at: sourceDir)
        }
        let source = sourceDir.appendingPathComponent("part.scad")
        try Data("include <shared.scad>\ncube(10);\n".utf8).write(to: source)

        let command = Recording()
        let renderer = OpenSCADRenderer(workDir: workDir, openSCAD: command)
        _ = try renderer.exportForGo3mf(scadFile: source)

        // By path rather than by URL: `deletingLastPathComponent()` leaves a
        // trailing slash and the directory it was made from does not, so two
        // URLs naming one directory compare unequal.
        let directories = Set(command.recorded.map { $0.workingDirectory.standardizedFileURL.path })
        XCTAssertTrue(directories.contains(sourceDir.standardizedFileURL.path), "\(directories)")
        XCTAssertTrue(directories.contains(workDir.standardizedFileURL.path), "\(directories)")
    }

    func testWithoutOneTheInstalledCopyIsStillWhatIsUsed() throws {
        // The default is the whole compatibility promise: a viewer nobody is
        // embedding, and every caller that has not been changed, behave exactly
        // as they did. There is no way to observe which command an
        // `OpenSCADRenderer` holds, so this asserts the next best thing — that
        // the type still constructs without one.
        let workDir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }
        XCTAssertNotNil(OpenSCADRenderer(workDir: workDir))
    }
}
