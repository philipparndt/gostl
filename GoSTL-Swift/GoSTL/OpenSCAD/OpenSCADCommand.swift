import Foundation

/// How to run OpenSCAD.
///
/// This used to be a function that answered with a *path*, and every caller
/// built a `Process` around it — a dozen times in `OpenSCADRenderer` alone.
/// That shape can only ever mean "a binary on this machine", which is the one
/// thing an embedder may want to change: an editor that already runs its tools
/// from container images has a perfectly good OpenSCAD and no installed copy,
/// and a user who has neither is told to go and fetch a 200 MB cask before a
/// `.scad` will preview at all.
///
/// So the seam answers with *how to run it* rather than with where it is. The
/// two things every call needs are the arguments — which name files by their
/// paths on this machine — and the directory to run in, and both are given per
/// call rather than once, because the renderer deliberately uses a different
/// working directory for different passes. See `OpenSCADRenderer`: relative
/// `include <…>` and `use <…>` resolve against the working directory, so a
/// model that includes the file beside it renders correctly only if that
/// directory is the one the renderer chose.
///
/// Injected rather than discovered, and defaulted to the installed copy, so a
/// viewer used on its own behaves exactly as it did before this existed.
public protocol OpenSCADCommand: Sendable {
    /// A process ready to be run and waited on.
    ///
    /// - Parameters:
    ///   - arguments: what OpenSCAD is to be passed, naming files by their paths
    ///     on this machine. An implementation that runs OpenSCAD somewhere else
    ///     has to translate them, and has to be able to say no.
    ///   - workingDirectory: what relative includes resolve against. Not a
    ///     property of the command: it changes per call.
    ///
    /// Standard output and standard error are the caller's to set; nothing here
    /// touches them.
    func makeProcess(arguments: [String], workingDirectory: URL) throws -> Process
}

/// OpenSCAD as installed on this machine, which is what a viewer running on its
/// own uses and what everything did before the protocol above existed.
public struct InstalledOpenSCAD: OpenSCADCommand {
    public init() {}

    public func makeProcess(arguments: [String], workingDirectory: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try Self.locate())
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        return process
    }

    /// Where OpenSCAD is, or `openSCADNotFound`.
    ///
    /// The cask puts it inside an application bundle and the three package
    /// managers each put it somewhere different, so the common places are tried
    /// before anything is launched — `which` costs a process, and this is asked
    /// once per pass and there are a dozen passes in one render.
    public static func locate() throws -> String {
        let commonPaths = [
            "/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD",
            "/usr/local/bin/openscad",
            "/opt/homebrew/bin/openscad",
            "/usr/bin/openscad"
        ]

        for path in commonPaths where FileManager.default.fileExists(atPath: path) {
            return path
        }

        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["openscad"]

        let whichPipe = Pipe()
        whichProcess.standardOutput = whichPipe
        whichProcess.standardError = Pipe()

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()

            // Read after waiting, which is the deadlock shape in general: a
            // process that fills the pipe's buffer blocks, and nobody is
            // draining it. It is safe here and only here — `which` prints one
            // short line and then exits — and it is worth knowing that the
            // reason is the size of the output rather than anything about this
            // code, because the same pattern around OpenSCAD itself would hang.
            if whichProcess.terminationStatus == 0 {
                let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // 'which' failed, continue to error
        }

        throw OpenSCADError.openSCADNotFound
    }
}
