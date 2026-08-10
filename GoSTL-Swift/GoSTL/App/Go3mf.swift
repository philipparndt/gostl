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
    private let workDir: URL

    /// Initialize renderer with a working directory
    init(workDir: URL) {
        self.workDir = workDir
    }

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

    /// Build a 3MF file from a YAML configuration using the go3mf CLI tool
    /// - Parameters:
    ///   - yamlFile: URL of the YAML configuration file
    ///   - outputFile: URL where the 3MF output should be written
    /// - Throws: Error if building fails
    func buildTo3MF(yamlFile: URL, outputFile: URL) throws {
        let go3mfPath = try findGo3mfExecutable()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: go3mfPath)
        process.arguments = ["build", yamlFile.path, "-o", outputFile.path]
        process.currentDirectoryURL = workDir

        // Inherit the user's shell PATH so go3mf can find openscad and other tools
        var environment = ProcessInfo.processInfo.environment
        if let shellPath = getShellPath() {
            environment["PATH"] = shellPath
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

            var errorMsg = "Failed to build \(yamlFile.lastPathComponent)\n"
            if !stderr.isEmpty {
                errorMsg += "stderr: \(stderr)\n"
            }
            if !stdout.isEmpty {
                errorMsg += "stdout: \(stdout)\n"
            }

            throw Go3mfError.buildFailed(errorMsg)
        }
    }
}

// MARK: - Open with go3mf menu command

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

/// Opens the current file with go3mf
func openWithGo3mf(sourceFileURL: URL?) {
    guard let sourceURL = sourceFileURL else {
        print("No file loaded")
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
    // Determine output filename: same as input but with .3mf extension
    let outputFileName = sourceURL.deletingPathExtension().lastPathComponent + ".3mf"
    let outputURL = sourceURL.deletingLastPathComponent().appendingPathComponent(outputFileName)

    // Execute go3mf build <filename> -o <output.3mf> --open
    let process = Process()
    process.executableURL = URL(fileURLWithPath: go3mfPath)
    process.arguments = ["build", sourceURL.path, "-o", outputURL.path, "--open"]
    process.currentDirectoryURL = sourceURL.deletingLastPathComponent()

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
                // Open the output file manually as a fallback
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
                let yamlURL = try generateGo3mfYAML(
                    exportResult: exportResult,
                    outputFileName: outputFileName,
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
    let process = Process()
    process.executableURL = URL(fileURLWithPath: go3mfPath)
    process.arguments = ["build", inputFile.path, "-o", outputFile.path, "--open"]
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

    print("Running: \(go3mfPath) build \(inputFile.path) -o \(outputFile.path) --open")
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
            // Open the output file manually as a fallback since --open may not work
            // reliably when running as a subprocess with captured stdout/stderr
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
