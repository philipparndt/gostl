import AppKit
import Foundation

/// Errors that can occur during go3mf operations
enum Go3mfError: LocalizedError {
    case go3mfNotFound
    case buildFailed(String)

    var errorDescription: String? {
        switch self {
        case .go3mfNotFound:
            return "go3mf not found. Please install go3mf first.\nChecked: /usr/local/bin/go3mf, /opt/homebrew/bin/go3mf, ~/go/bin/go3mf"
        case .buildFailed(let message):
            return message
        }
    }
}

/// Renderer that uses the external go3mf CLI tool to build 3MF files from YAML configs
class Go3mfToolRenderer {
    /// The name every directory this class builds in starts with.
    ///
    /// Public because it is also the proof that a directory is ours to delete:
    /// `removeTemporaryBuildArtifact(at:)` walks up from a built file looking
    /// for it, and removes nothing it does not find directly under the
    /// temporary directory carrying this prefix.
    static let buildDirectoryPrefix = "gostl-go3mf-build-"

    /// Find the go3mf executable path
    /// - Returns: Path to the go3mf executable
    /// - Throws: Go3mfError.go3mfNotFound if not found
    private func findGo3mfExecutable() throws -> String {
        // Common locations to check for go3mf on macOS
        let commonPaths = [
            "/usr/local/bin/go3mf",
            "/opt/homebrew/bin/go3mf",
            "/usr/bin/go3mf",
            NSHomeDirectory() + "/go/bin/go3mf",
            NSHomeDirectory() + "/.local/bin/go3mf"
        ]

        // Check common installation paths first
        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try using shell to find it (handles PATH from shell profile)
        let shellProcess = Process()
        let pipe = Pipe()

        // Use login shell to get full PATH
        shellProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shellProcess.arguments = ["-l", "-c", "which go3mf"]
        shellProcess.standardOutput = pipe
        shellProcess.standardError = FileHandle.nullDevice

        do {
            try shellProcess.run()
            shellProcess.waitUntilExit()

            if shellProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // Fall through
        }

        throw Go3mfError.go3mfNotFound
    }

    /// Get the user's shell PATH by running a login shell
    private func getShellPath() -> String? {
        let shellProcess = Process()
        let pipe = Pipe()

        // Use login shell to get full PATH
        shellProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shellProcess.arguments = ["-l", "-c", "echo $PATH"]
        shellProcess.standardOutput = pipe
        shellProcess.standardError = FileHandle.nullDevice

        do {
            try shellProcess.run()
            shellProcess.waitUntilExit()

            if shellProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // Fall through
        }

        return nil
    }

    /// Builds a go3mf recipe and returns the 3MF it produced.
    ///
    /// The recipe is built in a temporary directory of this method's own, and
    /// that is the whole point rather than tidiness. `go3mf build <recipe> -o
    /// <somewhere>` looks like it decides where the result goes; it does not.
    /// A single YAML input takes `CreatePlan` down `createYAMLPlan`, which is
    /// the one plan that never receives the `-o` value, and `LoadYAMLStep`
    /// takes the output from the recipe's own `output:` — which the loader
    /// requires, so every recipe has one. go3mf writes that name **relative to
    /// its working directory** and exits 0.
    ///
    /// So a viewer that ran go3mf in the recipe's own directory, as this did,
    /// wrote the recipe's declared output *into the project it was looking at*,
    /// over whatever was already there — a hand-made or hand-sliced `.3mf`
    /// under exactly that name is the normal case, since the recipe names it —
    /// and then read a temporary file that had never been created, failing with
    /// `NSCocoaErrorDomain 260`.
    ///
    /// The working directory is therefore the lever, and it is enough of one:
    /// go3mf's config loader resolves every `file:` against the *recipe's* own
    /// directory (`filepath.Join(absConfigDir, part.File)`), so the parts are
    /// still found where they live while the output lands where this method
    /// says. Nothing is copied and nothing is rewritten. Measured against
    /// go3mf 0.16.5 (d46a00a), which is the version this comment describes.
    ///
    /// - Parameter recipe: URL of the YAML recipe
    /// - Returns: URL of the built 3MF, inside a temporary directory
    /// - Throws: `Go3mfError` if go3mf is missing, the recipe declares an
    ///   output this program will not write, or the build produced nothing
    func buildRecipe(_ recipe: URL) throws -> URL {
        let go3mfPath = try findGo3mfExecutable()

        let recipeText: String
        do {
            recipeText = try String(contentsOf: recipe, encoding: .utf8)
        } catch {
            throw Go3mfError.buildFailed(
                "Could not read \(recipe.lastPathComponent): \(error.localizedDescription)"
            )
        }

        guard let declaredOutput = go3mfRecipeDeclaredOutput(inRecipe: recipeText) else {
            throw Go3mfError.buildFailed(
                """
                \(recipe.lastPathComponent) declares no output:

                A go3mf recipe must name the file it builds, and go3mf will
                refuse the recipe for the same reason.
                """
            )
        }

        let buildDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.buildDirectoryPrefix + UUID().uuidString, isDirectory: true)

        guard let outputURL = go3mfRecipeOutputURL(
            declared: declaredOutput,
            buildDirectory: buildDirectory
        ) else {
            throw Go3mfError.buildFailed(
                """
                \(recipe.lastPathComponent) declares output: \(declaredOutput)

                That names a file outside the directory this build would happen
                in, so building the recipe would write it. A viewer does not
                write to the project it is showing: it builds into a temporary
                directory of its own, which only works for an output: that is a
                relative path. Nothing was built and nothing was written.
                """
            )
        }

        // go3mf does not create the output's parent directory - it fails with
        // "error creating output file" - so an output: naming a subdirectory
        // needs that subdirectory to exist inside the build directory first.
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: go3mfPath)
        process.arguments = go3mfRecipeBuildArguments(recipe: recipe)
        process.currentDirectoryURL = buildDirectory

        // Inherit the user's shell PATH so go3mf can find openscad and other tools
        var environment = ProcessInfo.processInfo.environment
        if let shellPath = getShellPath() {
            environment["PATH"] = shellPath
        }
        process.environment = environment

        // Captured into files rather than pipes, deliberately. This waits for
        // go3mf to exit before reading anything, and a pipe nobody is draining
        // stops the writer once its buffer is full: go3mf prints a listing of
        // every object it built, so a large enough recipe would hang the viewer
        // rather than show it. Files cannot fill, they need no second thread,
        // and they go with the build directory around them.
        let stdoutURL = buildDirectory.appendingPathComponent("go3mf-stdout.txt")
        let stderrURL = buildDirectory.appendingPathComponent("go3mf-stderr.txt")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil, attributes: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil, attributes: nil)
        process.standardOutput = try FileHandle(forWritingTo: stdoutURL)
        process.standardError = try FileHandle(forWritingTo: stderrURL)

        try process.run()
        process.waitUntilExit()

        let stdout = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        func failure(_ headline: String) -> Go3mfError {
            var message = headline + "\n"
            if !stderr.isEmpty {
                message += "stderr: \(stderr)\n"
            }
            if !stdout.isEmpty {
                message += "stdout: \(stdout)\n"
            }
            return Go3mfError.buildFailed(message)
        }

        if process.terminationStatus != 0 {
            try? FileManager.default.removeItem(at: buildDirectory)
            throw failure("Failed to build \(recipe.lastPathComponent)")
        }

        // Asked rather than assumed, because the exit status has already been
        // wrong about this once: go3mf exited 0 having written the file
        // somewhere else entirely, and the failure surfaced much later as a
        // 3MF parser complaining about a file that was not there.
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            try? FileManager.default.removeItem(at: buildDirectory)
            throw failure(
                """
                go3mf reported success but wrote no \(outputURL.lastPathComponent)

                Expected it at \(outputURL.path), from the output: in \
                \(recipe.lastPathComponent).
                """
            )
        }

        return outputURL
    }
}

// MARK: - What a recipe says go3mf will write

/// The `output:` a go3mf recipe declares, which is the only thing that decides
/// the name of what go3mf writes for a recipe - `-o` does not (see
/// `Go3mfToolRenderer.buildRecipe`).
///
/// A deliberately small reader rather than a YAML parser: only a top-level
/// `output:` counts, which is what go3mf's own loader unmarshals, so a `file:`
/// or a nested key of the same name cannot be mistaken for it. Indentation is
/// the test - a top-level mapping key in YAML starts at column zero.
///
/// - Parameter text: the contents of the recipe
/// - Returns: the declared value, or nil if the recipe declares none
func go3mfRecipeDeclaredOutput(inRecipe text: String) -> String? {
    for line in text.components(separatedBy: .newlines) {
        guard line.hasPrefix("output:") else { continue }

        var value = String(line.dropFirst("output:".count))
            .trimmingCharacters(in: .whitespaces)

        // Nothing but a comment after the key is nothing.
        if value.hasPrefix("#") { return nil }

        // A quoted value keeps everything up to its closing quote, which is how
        // a '#' or a trailing space inside a filename survives.
        if let quote = value.first, quote == "\"" || quote == "'" {
            let body = value.dropFirst()
            if let end = body.firstIndex(of: quote) {
                let quoted = String(body[body.startIndex..<end])
                return quoted.isEmpty ? nil : quoted
            }
        }

        // Unquoted: YAML ends the value at an inline comment, which needs a
        // space before its '#'.
        if let comment = value.range(of: " #") {
            value = String(value[value.startIndex..<comment.lowerBound])
                .trimmingCharacters(in: .whitespaces)
        }

        return value.isEmpty ? nil : value
    }

    return nil
}

/// Where a recipe's declared output lands when go3mf runs in `buildDirectory`,
/// or nil when that is somewhere this program will not write.
///
/// go3mf resolves a relative `output:` against its working directory, so a
/// relative one lands inside the build directory and is ours to create. An
/// absolute one, or one that climbs out with `..`, does not - it names a file
/// in the project or anywhere else on the disk, and building the recipe would
/// overwrite it. That is the case this returns nil for: a viewer showing a file
/// must not modify what it is showing, and there is no working directory that
/// can contain an absolute path.
func go3mfRecipeOutputURL(declared: String, buildDirectory: URL) -> URL? {
    let root = buildDirectory.standardizedFileURL
    let resolved = URL(fileURLWithPath: declared, relativeTo: root).standardizedFileURL

    // Compared as paths with a trailing separator so that a sibling directory
    // whose name merely starts the same way ("...-build-1x/out.3mf" against
    // "...-build-1") cannot pass for a child.
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard resolved.path.hasPrefix(rootPath), resolved.path != rootPath else { return nil }

    return resolved
}

/// The arguments that build a recipe, which carry no `-o`.
///
/// Not an oversight and not shared with `go3mfBuildArguments`: for a YAML
/// recipe go3mf ignores `-o` entirely, and passing it said the opposite - that
/// this program had chosen where the output goes - while go3mf wrote the
/// recipe's own `output:` into whatever directory it happened to be run in.
/// The working directory is what decides it, so the working directory is what
/// `buildRecipe` sets.
func go3mfRecipeBuildArguments(recipe: URL) -> [String] {
    ["build", recipe.path]
}

/// Removes a built artifact, and the private build directory it sits in when
/// that directory is one this program made.
///
/// A recipe's `output:` may name a subdirectory, so the build directory is not
/// always the file's parent; this walks up to the nearest ancestor that is a
/// direct child of the temporary directory and carries
/// `Go3mfToolRenderer.buildDirectoryPrefix`. Finding neither, it deletes the
/// one file it was given and nothing else - the two conditions together are
/// what make a recursive delete safe to write here at all.
func removeTemporaryBuildArtifact(at url: URL) {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .resolvingSymlinksInPath().standardizedFileURL

    var candidate = url.resolvingSymlinksInPath().standardizedFileURL
        .deletingLastPathComponent()

    while candidate.path != "/" && !candidate.path.isEmpty {
        if candidate.deletingLastPathComponent().path == temporaryDirectory.path,
           candidate.lastPathComponent.hasPrefix(Go3mfToolRenderer.buildDirectoryPrefix) {
            try? FileManager.default.removeItem(at: candidate)
            return
        }
        candidate = candidate.deletingLastPathComponent()
    }

    try? FileManager.default.removeItem(at: url)
}

// MARK: - Open with go3mf

/// The arguments that build `output` from `input`, and nothing else.
///
/// One function, and it deliberately cannot ask go3mf to open the result. There
/// used to be two ways the built `.3mf` was opened and both of them ran: this
/// argument list ended in `--open`, and then the success branch called
/// `NSWorkspace.shared.open` on the same file "as a fallback since --open may
/// not work reliably when running as a subprocess with captured stdout/stderr".
/// It works perfectly reliably — `--open` is `exec.Command("open", file)` inside
/// go3mf — so one press of `o` handed the same file to the slicer twice and it
/// appeared twice (0481).
///
/// Opening is this program's job rather than go3mf's: it is the side that knows
/// the build finished, it can say so through the error overlay when it did not,
/// and `NSWorkspace` needs no `open` on the subprocess's `PATH`. Both call sites
/// build their arguments here, so a second `--open` cannot come back into one of
/// them without coming back into the other.
func go3mfBuildArguments(input: URL, output: URL) -> [String] {
    ["build", input.path, "-o", output.path]
}

/// Get the user's shell PATH by running a login shell
/// - Returns: The full PATH string from the user's shell environment
private func getShellPath() -> String? {
    let shellProcess = Process()
    let pipe = Pipe()

    // Use login shell to get full PATH
    shellProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
    shellProcess.arguments = ["-l", "-c", "echo $PATH"]
    shellProcess.standardOutput = pipe
    shellProcess.standardError = FileHandle.nullDevice

    do {
        try shellProcess.run()
        shellProcess.waitUntilExit()

        if shellProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }
    } catch {
        // Fall through
    }

    return nil
}

/// Find the go3mf executable path
/// - Returns: Path to the go3mf executable, or nil if not found
private func findGo3mfExecutable() -> String? {
    // Common locations to check for go3mf on macOS
    let commonPaths = [
        "/usr/local/bin/go3mf",
        "/opt/homebrew/bin/go3mf",
        "/usr/bin/go3mf",
        NSHomeDirectory() + "/go/bin/go3mf",
        NSHomeDirectory() + "/.local/bin/go3mf"
    ]

    // Check common installation paths first
    for path in commonPaths {
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }

    // Try using shell to find it (handles PATH from shell profile)
    let shellProcess = Process()
    let pipe = Pipe()

    // Use login shell to get full PATH
    shellProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
    shellProcess.arguments = ["-l", "-c", "which go3mf"]
    shellProcess.standardOutput = pipe
    shellProcess.standardError = FileHandle.nullDevice

    do {
        try shellProcess.run()
        shellProcess.waitUntilExit()

        if shellProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }
    } catch {
        // Fall through
    }

    return nil
}

extension AppState {
    /// Builds the file this viewer is showing and opens the result.
    ///
    /// A method on the state rather than a free function reached through a
    /// broadcast, which is what it was: `OpenWithGo3mf` went to every live
    /// `AppState` and each answered with its own `sourceFileURL`, so one
    /// command built and opened a file per open window — none of which was
    /// necessarily the one in front. The menu, the panel's button and the
    /// viewport's `o` all arrive here, at the viewer they mean (0481).
    func openWithGo3mf() {
        buildAndOpenWithGo3mf(sourceFileURL: sourceFileURL)
    }
}

/// Builds the given file with go3mf and opens what it produced.
///
/// Private, and reached only through `AppState.openWithGo3mf()`: which file is
/// opened is a property of a viewer, and passing one in by hand is how a single
/// command came to act on a window that was not the one in front.
/// Whether this file is already what a build would have produced.
///
/// `openFileWithGo3mf` takes the output's name from the input for anything that
/// is not a recipe — `x.stl` becomes `x.3mf` beside it — so for a file that is
/// *already* a `.3mf` the input and the output are the same path, and the
/// command becomes `go3mf build x.3mf -o x.3mf`. go3mf reads that as combining a
/// set of one and refuses, correctly:
///
///     ✓ Validated 1 3MF file(s)
///     Merging 3MF files...
///     ✗ at least 2 files required for combining
///
/// which reached the viewer as "Failed to build x.3mf" — a build failure for a
/// file that needs no building. There is nothing to make here: the file is
/// already the thing, so it is handed straight to whatever opens a 3MF.
///
/// A recipe is never this, whatever it is called: what it produces is named by
/// its own `output:`, so it is asked about the extension and not about the
/// question this answers.
func isAlreadyBuilt(_ sourceURL: URL) -> Bool {
    sourceURL.pathExtension.lowercased() == "3mf"
}

private func buildAndOpenWithGo3mf(sourceFileURL: URL?) {
    guard let sourceURL = sourceFileURL else {
        print("No file loaded")
        return
    }

    // Nothing to build, so nothing is built. The successful build below ends in
    // exactly this call; a 3MF simply starts there.
    //
    // Before `findGo3mfExecutable`, deliberately: opening a 3MF needs no go3mf
    // at all, and failing with "go3mf not found" on a machine that does not have
    // it would be the same wrong answer in a different sentence.
    if isAlreadyBuilt(sourceURL) {
        print("\(sourceURL.lastPathComponent) is already a 3MF — opening it rather than building it")
        NSWorkspace.shared.open(sourceURL)
        return
    }

    // Find go3mf executable
    guard let go3mfPath = findGo3mfExecutable() else {
        let error = Go3mfError.go3mfNotFound
        print("go3mf not found. Please install go3mf first.")
        print("Checked: /usr/local/bin/go3mf, /opt/homebrew/bin/go3mf, ~/go/bin/go3mf")
        NotificationCenter.default.post(name: NSNotification.Name("Go3mfError"), object: error)
        return
    }

    print("Opening \(sourceURL.path) with go3mf at \(go3mfPath)...")

    // Check if this is an OpenSCAD file - try multi-color export
    let isOpenSCAD = sourceURL.pathExtension.lowercased() == "scad"

    if isOpenSCAD {
        openOpenSCADWithGo3mf(sourceURL: sourceURL, go3mfPath: go3mfPath)
    } else {
        openFileWithGo3mf(sourceURL: sourceURL, go3mfPath: go3mfPath)
    }
}

/// Open a regular file (STL, 3MF, YAML) with go3mf
private func openFileWithGo3mf(sourceURL: URL, go3mfPath: String) {
    // Where the result goes, and it is not the same question for a recipe.
    //
    // Pressing `o` is an export somebody asked for, so it writing into the
    // project is the point - unlike showing a recipe in the viewer, which must
    // not (see `Go3mfToolRenderer.buildRecipe`). But go3mf still takes the name
    // from the recipe's own `output:` and not from `-o`, so the file this then
    // hands to the slicer has to be the one the recipe named: a recipe whose
    // output: is anything other than its own basename used to build correctly
    // and then open a path that had never existed.
    let isRecipe = ["yaml", "yml"].contains(sourceURL.pathExtension.lowercased())
    let recipeDirectory = sourceURL.deletingLastPathComponent()
    let declaredOutput = isRecipe
        ? (try? String(contentsOf: sourceURL, encoding: .utf8)).flatMap(go3mfRecipeDeclaredOutput(inRecipe:))
        : nil

    let outputURL: URL
    if let declaredOutput {
        outputURL = URL(fileURLWithPath: declaredOutput, relativeTo: recipeDirectory)
    } else {
        outputURL = recipeDirectory
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + ".3mf")
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: go3mfPath)
    process.arguments = isRecipe
        ? go3mfRecipeBuildArguments(recipe: sourceURL)
        : go3mfBuildArguments(input: sourceURL, output: outputURL)
    process.currentDirectoryURL = recipeDirectory

    // Inherit the user's shell PATH so go3mf can find openscad and other tools
    var environment = ProcessInfo.processInfo.environment
    if let shellPath = getShellPath() {
        environment["PATH"] = shellPath
    }
    process.environment = environment

    // Capture stdout and stderr to show errors
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
        try process.run()

        // Run in background to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

                var errorMsg = "Failed to build \(sourceURL.lastPathComponent)\n"
                if !stderr.isEmpty {
                    errorMsg += stderr
                }
                if !stdout.isEmpty {
                    if !stderr.isEmpty { errorMsg += "\n" }
                    errorMsg += stdout
                }

                let error = Go3mfError.buildFailed(errorMsg)
                print("go3mf error: \(errorMsg)")

                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("Go3mfError"), object: error)
                }
            } else {
                print("go3mf build completed successfully")
                // The one place the result is opened. See go3mfBuildArguments.
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(outputURL)
                }
            }
        }
    } catch {
        print("Error launching go3mf: \(error)")
        let go3mfError = Go3mfError.buildFailed("Failed to launch go3mf: \(error.localizedDescription)")
        NotificationCenter.default.post(name: NSNotification.Name("Go3mfError"), object: go3mfError)
    }
}

/// Open an OpenSCAD file with go3mf, supporting multi-color export
private func openOpenSCADWithGo3mf(sourceURL: URL, go3mfPath: String) {
    // Run export in background to avoid blocking UI
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            let tempDir = FileManager.default.temporaryDirectory
            // The installed copy, deliberately. This path hands what it makes
            // to the `go3mf` binary on this machine a few lines down, so it is
            // a host path from end to end and an embedder's command would be
            // the odd one out — and there is no AppState here to ask for one.
            let renderer = OpenSCADRenderer(workDir: tempDir)

            print("Exporting OpenSCAD file for go3mf...")
            let exportResult = try renderer.exportForGo3mf(scadFile: sourceURL)

            // Determine output path
            let outputFileName = sourceURL.deletingPathExtension().lastPathComponent + ".3mf"
            let outputURL = sourceURL.deletingLastPathComponent().appendingPathComponent(outputFileName)

            if exportResult.isMultiColor {
                // Generate YAML config for multi-color
                print("Multi-color model detected (\(exportResult.parts.count) parts), generating go3mf config...")
                for (i, part) in exportResult.parts.enumerated() {
                    let partPath = exportResult.outputDir.appendingPathComponent(part.filename)
                    let attrs = try? FileManager.default.attributesOfItem(atPath: partPath.path)
                    let size = attrs?[.size] as? Int ?? 0
                    print("  Part \(i + 1): \(part.filename) (\(size) bytes) - color: \(part.color?.description ?? "none")")
                }
                // The absolute destination, in the recipe rather than in `-o`.
                // This recipe is generated a few lines up rather than written
                // by anybody, so `output:` is the honest place to say where the
                // export goes - and it is the only place go3mf reads it from
                // for a recipe, whatever `-o` says (see
                // `Go3mfToolRenderer.buildRecipe`). With the name alone here,
                // go3mf wrote it into the temporary export directory that
                // `cleanup` then deleted, and the file the success branch
                // handed to the slicer had never existed.
                let yamlURL = try generateGo3mfYAML(
                    exportResult: exportResult,
                    outputFileName: outputURL.path,
                    modelName: sourceURL.deletingPathExtension().lastPathComponent
                )

                // Build with go3mf
                runGo3mf(
                    go3mfPath: go3mfPath,
                    inputFile: yamlURL,
                    outputFile: outputURL,
                    workDir: exportResult.outputDir,
                    cleanup: {
                        // Clean up temp directory after build
                        try? FileManager.default.removeItem(at: exportResult.outputDir)
                    }
                )
            } else {
                // Single color - use the STL directly
                print("Single color model, using standard go3mf build...")
                let stlURL = exportResult.outputDir.appendingPathComponent(exportResult.parts[0].filename)

                runGo3mf(
                    go3mfPath: go3mfPath,
                    inputFile: stlURL,
                    outputFile: outputURL,
                    workDir: exportResult.outputDir,
                    cleanup: {
                        try? FileManager.default.removeItem(at: exportResult.outputDir)
                    }
                )
            }
        } catch {
            print("Error exporting OpenSCAD for go3mf: \(error)")
            DispatchQueue.main.async {
                let go3mfError = Go3mfError.buildFailed("Failed to export OpenSCAD: \(error.localizedDescription)")
                NotificationCenter.default.post(name: NSNotification.Name("Go3mfError"), object: go3mfError)
            }
        }
    }
}

/// Generate a go3mf YAML configuration file for multi-color export
private func generateGo3mfYAML(
    exportResult: OpenSCADRenderer.Go3mfExportResult,
    outputFileName: String,
    modelName: String
) throws -> URL {
    var yaml = """
    output: \(outputFileName)

    objects:
      - name: \(modelName)
        parts:

    """

    for (index, part) in exportResult.parts.enumerated() {
        let filament = index + 1
        let partName = part.color?.description ?? "part_\(filament)"

        yaml += """
          - name: \(partName)
            file: \(part.filename)
            filament: \(filament)

    """
    }

    let yamlURL = exportResult.outputDir.appendingPathComponent("config.yaml")
    try yaml.write(to: yamlURL, atomically: true, encoding: .utf8)
    print("Generated go3mf config at: \(yamlURL.path)")
    print("YAML content:\n\(yaml)")
    return yamlURL
}

/// Run go3mf build command
private func runGo3mf(
    go3mfPath: String,
    inputFile: URL,
    outputFile: URL,
    workDir: URL,
    cleanup: @escaping () -> Void
) {
    // A recipe carries its own destination and ignores `-o`; anything else
    // (an STL, a 3MF) takes it from `-o`. See `Go3mfToolRenderer.buildRecipe`.
    let isRecipe = ["yaml", "yml"].contains(inputFile.pathExtension.lowercased())

    let process = Process()
    process.executableURL = URL(fileURLWithPath: go3mfPath)
    process.arguments = isRecipe
        ? go3mfRecipeBuildArguments(recipe: inputFile)
        : go3mfBuildArguments(input: inputFile, output: outputFile)
    process.currentDirectoryURL = workDir

    // Inherit the user's shell PATH
    var environment = ProcessInfo.processInfo.environment
    if let shellPath = getShellPath() {
        environment["PATH"] = shellPath
    }
    process.environment = environment

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    print("Running: \(go3mfPath) \(process.arguments!.joined(separator: " "))")
    print("Working directory: \(workDir.path)")

    do {
        try process.run()
        process.waitUntilExit()

        // Read output before cleanup
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

        if !stdout.isEmpty {
            print("go3mf stdout: \(stdout)")
        }
        if !stderr.isEmpty {
            print("go3mf stderr: \(stderr)")
        }

        cleanup()

        if process.terminationStatus != 0 {
            var errorMsg = "Failed to build \(inputFile.lastPathComponent)\n"
            if !stderr.isEmpty { errorMsg += stderr }
            if !stdout.isEmpty {
                if !stderr.isEmpty { errorMsg += "\n" }
                errorMsg += stdout
            }

            let error = Go3mfError.buildFailed(errorMsg)
            print("go3mf error: \(errorMsg)")

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("Go3mfError"), object: error)
            }
        } else {
            print("go3mf build completed successfully, output: \(outputFile.path)")
            // The one place the result is opened. See go3mfBuildArguments.
            DispatchQueue.main.async {
                NSWorkspace.shared.open(outputFile)
            }
        }
    } catch {
        cleanup()
        print("Error launching go3mf: \(error)")
        DispatchQueue.main.async {
            let go3mfError = Go3mfError.buildFailed("Failed to launch go3mf: \(error.localizedDescription)")
            NotificationCenter.default.post(name: NSNotification.Name("Go3mfError"), object: go3mfError)
        }
    }
}
