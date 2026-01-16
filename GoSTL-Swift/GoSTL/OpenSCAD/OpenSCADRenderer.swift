import Foundation

/// Handles OpenSCAD file rendering to STL format
class OpenSCADRenderer {
    private let workDir: URL

    /// Initialize renderer with a working directory
    init(workDir: URL) {
        self.workDir = workDir
    }

    /// Find the OpenSCAD executable path
    /// - Returns: Path to the OpenSCAD executable
    /// - Throws: OpenSCADError.openSCADNotFound if not found
    private func findOpenSCADExecutable() throws -> String {
        // Common locations to check for OpenSCAD on macOS
        let commonPaths = [
            "/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD",
            "/usr/local/bin/openscad",
            "/opt/homebrew/bin/openscad",
            "/usr/bin/openscad"
        ]

        // Check common installation paths first
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try to find via 'which' command
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["openscad"]

        let whichPipe = Pipe()
        whichProcess.standardOutput = whichPipe
        whichProcess.standardError = Pipe()

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()

            if whichProcess.terminationStatus == 0 {
                let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // 'which' failed, continue to error
        }

        throw OpenSCADError.openSCADNotFound
    }

    /// Result of an OpenSCAD render operation
    struct RenderResult {
        let warnings: [String]
        let is2D: Bool
    }

    /// Height to extrude 2D objects for visualization (in mm)
    private let extrude2DHeight: Double = 1.0

    /// Render an OpenSCAD file to STL format
    /// - Parameters:
    ///   - scadFile: URL of the .scad file to render
    ///   - outputFile: URL where the STL output should be written
    /// - Returns: RenderResult containing any warnings and whether it was a 2D file
    /// - Throws: Error if rendering fails
    func renderToSTL(scadFile: URL, outputFile: URL) throws -> RenderResult {
        // First try to render normally
        let result = try runOpenSCAD(scadFile: scadFile, outputFile: outputFile)

        // Check if the file produced empty geometry (likely a 2D file)
        if result.isEmpty {
            // Try rendering as 2D by wrapping with linear_extrude
            let wrapperFile = try create2DWrapperFile(for: scadFile)
            defer {
                try? FileManager.default.removeItem(at: wrapperFile)
            }

            let extrudedResult = try runOpenSCAD(scadFile: wrapperFile, outputFile: outputFile)

            if extrudedResult.isEmpty {
                // Still empty, throw the original error
                throw OpenSCADError.emptyFile(messages: result.messages)
            }

            // Success! Combine messages from both attempts
            var allMessages = result.messages
            allMessages.append(contentsOf: extrudedResult.messages)
            return RenderResult(warnings: allMessages, is2D: true)
        }

        return RenderResult(warnings: result.messages, is2D: false)
    }

    /// Internal result from running OpenSCAD
    private struct InternalRenderResult {
        let messages: [String]
        let isEmpty: Bool
        let errorMessage: String?
    }

    /// Run the OpenSCAD process
    /// - Parameters:
    ///   - scadFile: URL of the .scad file to render
    ///   - outputFile: URL where the STL output should be written
    /// - Returns: InternalRenderResult with messages and empty status
    /// - Throws: Error if rendering fails (except for empty file which returns isEmpty=true)
    private func runOpenSCAD(scadFile: URL, outputFile: URL) throws -> InternalRenderResult {
        // Find OpenSCAD executable
        let openscadPath = try findOpenSCADExecutable()

        // Run openscad command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: openscadPath)
        process.arguments = [
            "-o", outputFile.path,
            scadFile.path
        ]
        process.currentDirectoryURL = workDir

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        // Capture both stdout and stderr
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        // Parse messages from both stdout (ECHO) and stderr (warnings, errors)
        let messages = parseMessages(stdout: stdout, stderr: stderr)

        if process.terminationStatus != 0 {
            // Check if the file is empty or 2D-only (produces no 3D geometry)
            // "Current top level object is empty" - no geometry at all
            // "Current top level object is not a 3D object" - 2D geometry only
            if stderr.contains("Current top level object is empty") ||
               stderr.contains("Current top level object is not a 3D object") {
                return InternalRenderResult(messages: messages, isEmpty: true, errorMessage: nil)
            }

            var errorMsg = "Failed to render \(scadFile.lastPathComponent)\n"
            if !stderr.isEmpty {
                errorMsg += "stderr: \(stderr)\n"
            }
            if !stdout.isEmpty {
                errorMsg += "stdout: \(stdout)\n"
            }

            throw OpenSCADError.renderFailed(errorMsg, messages: messages)
        }

        return InternalRenderResult(messages: messages, isEmpty: false, errorMessage: nil)
    }

    /// Create a temporary wrapper file that extrudes 2D content for visualization
    /// - Parameter scadFile: The original 2D OpenSCAD file
    /// - Returns: URL to the temporary wrapper file
    private func create2DWrapperFile(for scadFile: URL) throws -> URL {
        // Wrap the include in a module, then extrude the module call
        // This is necessary because include statements must be at top level
        // but we need the geometry inside the linear_extrude block
        let wrapperContent = """
        // Temporary wrapper to extrude 2D content for visualization
        module _gostl_2d_content() {
            include <\(scadFile.path)>
        }

        linear_extrude(height = \(extrude2DHeight)) _gostl_2d_content();
        """

        let wrapperFile = workDir.appendingPathComponent("gostl_2d_wrapper_\(ProcessInfo.processInfo.processIdentifier).scad")
        try wrapperContent.write(to: wrapperFile, atomically: true, encoding: .utf8)

        return wrapperFile
    }

    /// Parse messages from OpenSCAD output
    /// - Parameters:
    ///   - stdout: Standard output (contains ECHO statements)
    ///   - stderr: Standard error (contains warnings, deprecations, errors)
    /// - Returns: Array of message strings
    private func parseMessages(stdout: String, stderr: String) -> [String] {
        var messages: [String] = []

        // Parse stdout for ECHO statements
        for line in stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ECHO:") {
                messages.append(trimmed)
            }
        }

        // Parse stderr for warnings, deprecations, errors, and traces
        for line in stderr.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("WARNING:") || trimmed.hasPrefix("DEPRECATED:") ||
               trimmed.hasPrefix("ERROR:") || trimmed.hasPrefix("TRACE:") {
                messages.append(trimmed)
            }
        }

        return messages
    }

    /// Resolve all dependencies (use/include statements) in an OpenSCAD file
    /// - Parameter scadFile: URL of the .scad file to analyze
    /// - Returns: Array of absolute file URLs for all dependencies (including the source file)
    ///           Missing files are skipped with a warning
    func resolveDependencies(scadFile: URL) -> [URL] {
        var visited = Set<URL>()
        var deps: [URL] = []

        resolveDependenciesRecursive(scadFile: scadFile, visited: &visited, deps: &deps)

        return deps
    }

    /// Recursively resolve dependencies to handle nested includes
    private func resolveDependenciesRecursive(scadFile: URL, visited: inout Set<URL>, deps: inout [URL]) {
        // Avoid circular dependencies
        let absolutePath = scadFile.standardizedFileURL
        guard !visited.contains(absolutePath) else {
            return
        }
        visited.insert(absolutePath)

        // Check if file exists before trying to read it
        guard FileManager.default.fileExists(atPath: absolutePath.path) else {
            print("OpenSCADRenderer: Skipping missing dependency: \(absolutePath.lastPathComponent)")
            return
        }

        // Add this file to dependencies
        deps.append(absolutePath)

        // Parse the file to find use/include statements
        guard let fileDeps = try? parseDependencies(scadFile: scadFile) else {
            print("OpenSCADRenderer: Could not parse dependencies in: \(scadFile.lastPathComponent)")
            return
        }

        // Recursively resolve dependencies
        for dep in fileDeps {
            resolveDependenciesRecursive(scadFile: dep, visited: &visited, deps: &deps)
        }
    }

    /// Parse a single OpenSCAD file to find use/include statements
    private func parseDependencies(scadFile: URL) throws -> [URL] {
        let content = try String(contentsOf: scadFile, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var deps: [URL] = []
        let scadDir = scadFile.deletingLastPathComponent()

        // Regular expressions to match use/include statements
        // Matches: use <file.scad>, include <file.scad>, use <./file.scad>, etc.
        // Also matches quoted forms: use "file.scad", include "file.scad"
        let useAnglePattern = #"^\s*use\s*<([^>]+)>"#
        let includeAnglePattern = #"^\s*include\s*<([^>]+)>"#
        let useQuotedPattern = #"^\s*use\s*\"([^\"]+)\""#
        let includeQuotedPattern = #"^\s*include\s*\"([^\"]+)\""#

        let useAngleRegex = try NSRegularExpression(pattern: useAnglePattern, options: [])
        let includeAngleRegex = try NSRegularExpression(pattern: includeAnglePattern, options: [])
        let useQuotedRegex = try NSRegularExpression(pattern: useQuotedPattern, options: [])
        let includeQuotedRegex = try NSRegularExpression(pattern: includeQuotedPattern, options: [])

        for line in lines {
            // Skip comments
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                continue
            }

            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            // Try all patterns and collect matches
            let allPatterns: [NSRegularExpression] = [
                useAngleRegex, includeAngleRegex, useQuotedRegex, includeQuotedRegex
            ]

            for regex in allPatterns {
                if let match = regex.firstMatch(in: line, options: [], range: range) {
                    let depPathRange = match.range(at: 1)
                    if depPathRange.location != NSNotFound {
                        let depPath = nsLine.substring(with: depPathRange)
                        let depURL = resolveDepPath(depPath: depPath, currentDir: scadDir)
                        deps.append(depURL)
                    }
                }
            }
        }

        return deps
    }

    /// Resolve a dependency path relative to the current file's directory
    private func resolveDepPath(depPath: String, currentDir: URL) -> URL {
        // If the path starts with ./ or ../, it's relative to the current file
        if depPath.hasPrefix("./") || depPath.hasPrefix("../") {
            return currentDir.appendingPathComponent(depPath).standardizedFileURL
        }

        // Try relative to current directory first
        let currentDirPath = currentDir.appendingPathComponent(depPath).standardizedFileURL
        if FileManager.default.fileExists(atPath: currentDirPath.path) {
            return currentDirPath
        }

        // Try relative to work directory
        let workDirPath = workDir.appendingPathComponent(depPath).standardizedFileURL
        if FileManager.default.fileExists(atPath: workDirPath.path) {
            return workDirPath
        }

        return currentDirPath  // Return the expected path even if not found
    }
}

/// Errors that can occur during OpenSCAD operations
enum OpenSCADError: LocalizedError {
    case openSCADNotFound
    case renderFailed(String, messages: [String])
    case emptyFile(messages: [String])

    var errorDescription: String? {
        switch self {
        case .openSCADNotFound:
            return "OpenSCAD not found in PATH. Please install OpenSCAD from https://openscad.org/"
        case .renderFailed(let message, _):
            return message
        case .emptyFile:
            return "The OpenSCAD file produced no geometry"
        }
    }

    /// Get messages associated with the error (warnings, echoes, errors, traces)
    var messages: [String] {
        switch self {
        case .openSCADNotFound:
            return []
        case .renderFailed(_, let messages):
            return messages
        case .emptyFile(let messages):
            return messages
        }
    }
}
