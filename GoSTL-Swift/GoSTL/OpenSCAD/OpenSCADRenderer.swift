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

    /// Render an OpenSCAD file to STL format
    /// - Parameters:
    ///   - scadFile: URL of the .scad file to render
    ///   - outputFile: URL where the STL output should be written
    /// - Throws: Error if rendering fails
    func renderToSTL(scadFile: URL, outputFile: URL) throws {
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

        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

            var errorMsg = "Failed to render \(scadFile.lastPathComponent)\n"
            if let stderr = String(data: stderrData, encoding: .utf8), !stderr.isEmpty {
                errorMsg += "stderr: \(stderr)\n"
            }
            if let stdout = String(data: stdoutData, encoding: .utf8), !stdout.isEmpty {
                errorMsg += "stdout: \(stdout)\n"
            }

            throw OpenSCADError.renderFailed(errorMsg)
        }
    }

    /// Resolve all dependencies (use/include statements) in an OpenSCAD file
    /// - Parameter scadFile: URL of the .scad file to analyze
    /// - Returns: Array of absolute file URLs for all dependencies (including the source file)
    /// - Throws: Error if file cannot be read or dependencies cannot be resolved
    func resolveDependencies(scadFile: URL) throws -> [URL] {
        var visited = Set<URL>()
        var deps: [URL] = []

        try resolveDependenciesRecursive(scadFile: scadFile, visited: &visited, deps: &deps)

        return deps
    }

    /// Recursively resolve dependencies to handle nested includes
    private func resolveDependenciesRecursive(scadFile: URL, visited: inout Set<URL>, deps: inout [URL]) throws {
        // Avoid circular dependencies
        let absolutePath = scadFile.standardizedFileURL
        guard !visited.contains(absolutePath) else {
            return
        }
        visited.insert(absolutePath)

        // Add this file to dependencies
        deps.append(absolutePath)

        // Parse the file to find use/include statements
        let fileDeps = try parseDependencies(scadFile: scadFile)

        // Recursively resolve dependencies
        for dep in fileDeps {
            try resolveDependenciesRecursive(scadFile: dep, visited: &visited, deps: &deps)
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
        let usePattern = #"^\s*use\s*<([^>]+)>"#
        let includePattern = #"^\s*include\s*<([^>]+)>"#

        let useRegex = try NSRegularExpression(pattern: usePattern, options: [])
        let includeRegex = try NSRegularExpression(pattern: includePattern, options: [])

        for line in lines {
            // Skip comments
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                continue
            }

            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            // Check for use statement
            if let match = useRegex.firstMatch(in: line, options: [], range: range) {
                let depPathRange = match.range(at: 1)
                if depPathRange.location != NSNotFound {
                    let depPath = nsLine.substring(with: depPathRange)
                    let depURL = resolveDepPath(depPath: depPath, currentDir: scadDir)
                    deps.append(depURL)
                }
            }

            // Check for include statement
            if let match = includeRegex.firstMatch(in: line, options: [], range: range) {
                let depPathRange = match.range(at: 1)
                if depPathRange.location != NSNotFound {
                    let depPath = nsLine.substring(with: depPathRange)
                    let depURL = resolveDepPath(depPath: depPath, currentDir: scadDir)
                    deps.append(depURL)
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
        return workDir.appendingPathComponent(depPath).standardizedFileURL
    }
}

/// Errors that can occur during OpenSCAD operations
enum OpenSCADError: LocalizedError {
    case openSCADNotFound
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .openSCADNotFound:
            return "OpenSCAD not found in PATH. Please install OpenSCAD from https://openscad.org/"
        case .renderFailed(let message):
            return message
        }
    }
}
