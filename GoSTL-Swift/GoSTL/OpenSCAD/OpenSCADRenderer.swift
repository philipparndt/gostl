import Foundation

/// Represents an RGBA color extracted from OpenSCAD
struct OpenSCADColor: Hashable, CustomStringConvertible {
    let r: Float
    let g: Float
    let b: Float
    let a: Float

    /// Original string representation from OpenSCAD (for exact matching)
    let originalString: String

    /// Parse color from OpenSCAD string representation like "[1, 0, 0, 1]" or "[0.5, 0.25, 0.75]"
    init?(fromOpenSCADString str: String) {
        // Store the original string for exact matching
        self.originalString = str.trimmingCharacters(in: .whitespaces)

        // Remove brackets and split by comma
        let cleaned = originalString
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")

        let components = cleaned.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }

        guard components.count >= 3 else { return nil }

        self.r = components[0]
        self.g = components[1]
        self.b = components[2]
        self.a = components.count >= 4 ? components[3] : 1.0
    }

    init(r: Float, g: Float, b: Float, a: Float = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
        // Generate string that matches OpenSCAD format
        self.originalString = "[\(Self.formatComponent(r)), \(Self.formatComponent(g)), \(Self.formatComponent(b)), \(Self.formatComponent(a))]"
    }

    /// Format a component to match OpenSCAD's output (no decimal for whole numbers)
    private static func formatComponent(_ value: Float) -> String {
        if value == Float(Int(value)) {
            return String(Int(value))
        } else {
            return String(value)
        }
    }

    /// String to use for matching in OpenSCAD module redefinition
    var openSCADString: String {
        originalString
    }

    /// Convert to TriangleColor
    var triangleColor: TriangleColor {
        TriangleColor(r, g, b, a)
    }

    var description: String {
        "RGBA(\(r), \(g), \(b), \(a))"
    }

    /// Check if this is effectively white (uses material color)
    var isWhite: Bool {
        r > 0.99 && g > 0.99 && b > 0.99
    }

    /// Hash based on original string for Set membership
    func hash(into hasher: inout Hasher) {
        hasher.combine(originalString)
    }

    /// Equality based on original string
    static func == (lhs: OpenSCADColor, rhs: OpenSCADColor) -> Bool {
        lhs.originalString == rhs.originalString
    }
}

/// Handles OpenSCAD file rendering to STL format
class OpenSCADRenderer {
    private let workDir: URL

    /// Unique tag for color extraction
    private let colorTag = "GOSTL_COLOR"

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

    /// Result of a colored OpenSCAD render operation
    struct ColoredRenderResult {
        let model: STLModel
        let warnings: [String]
        let is2D: Bool
        let colorsExtracted: Int
    }

    /// Height to extrude 2D objects for visualization (in mm)
    private let extrude2DHeight: Double = 1.0

    // MARK: - Colored Rendering

    /// Render an OpenSCAD file to a colored STL model
    /// This uses the colorscad technique: extract colors via echo, render each color separately
    /// - Parameters:
    ///   - scadFile: URL of the .scad file to render
    /// - Returns: ColoredRenderResult containing the model with per-triangle colors
    /// - Throws: Error if rendering fails
    func renderToColoredModel(scadFile: URL) throws -> ColoredRenderResult {
        let t0 = CFAbsoluteTimeGetCurrent()

        // Generate unique session ID for this render operation to avoid conflicts
        // when multiple models are rendered simultaneously
        let sessionId = UUID().uuidString.prefix(8)

        // Step 1: Convert to CSG format (normalizes all color() calls)
        let csgFile = workDir.appendingPathComponent("gostl_\(sessionId).csg")
        defer { try? FileManager.default.removeItem(at: csgFile) }

        do {
            try convertToCSG(scadFile: scadFile, outputFile: csgFile)
        } catch {
            // CSG conversion failed, fall back to regular rendering
            print("CSG conversion failed, falling back to non-colored rendering: \(error)")
            return try renderWithoutColors(scadFile: scadFile)
        }

        print("  CSG conversion: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")

        // Step 2: Extract all unique colors used in the model
        let t1 = CFAbsoluteTimeGetCurrent()
        let colors = try extractColors(csgFile: csgFile, sessionId: sessionId)
        print("  Color extraction: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t1) * 1000))ms - found \(colors.count) colors")

        // If no colors, use regular rendering
        if colors.isEmpty {
            print("  No colors found, using standard rendering")
            return try renderWithoutColors(scadFile: scadFile, sessionId: sessionId)
        }

        // Step 3: Check for uncolored geometry (will be rendered with default material color)
        let t2 = CFAbsoluteTimeGetCurrent()
        let hasUncoloredGeometry = try checkForUncoloredGeometry(csgFile: csgFile, sessionId: sessionId)
        print("  Uncolored check: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t2) * 1000))ms - has uncolored: \(hasUncoloredGeometry)")

        // Step 4: Render each color separately in parallel (plus uncolored if present)
        let t3 = CFAbsoluteTimeGetCurrent()
        let coloredTriangles = try renderColorsInParallel(csgFile: csgFile, colors: Array(colors), includeUncolored: hasUncoloredGeometry, sessionId: sessionId)
        print("  Per-color rendering: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t3) * 1000))ms")

        // Step 5: Combine all triangles into a single model
        let model = STLModel(triangles: coloredTriangles, name: scadFile.deletingPathExtension().lastPathComponent)

        print("  Total colored rendering: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")

        // Collect any warnings from the CSG file
        let warnings = try? extractWarnings(csgFile: csgFile, sessionId: sessionId)

        return ColoredRenderResult(
            model: model,
            warnings: warnings ?? [],
            is2D: false,
            colorsExtracted: colors.count
        )
    }

    /// Fall back to regular (non-colored) rendering
    private func renderWithoutColors(scadFile: URL, sessionId: String.SubSequence? = nil) throws -> ColoredRenderResult {
        let id = sessionId ?? UUID().uuidString.prefix(8)
        let tempSTL = workDir.appendingPathComponent("gostl_\(id).stl")
        defer { try? FileManager.default.removeItem(at: tempSTL) }

        let result = try runOpenSCAD(scadFile: scadFile, outputFile: tempSTL)

        if result.isEmpty {
            // Try 2D extrusion
            let wrapperFile = try create2DWrapperFile(for: scadFile)
            defer { try? FileManager.default.removeItem(at: wrapperFile) }

            let extrudedResult = try runOpenSCAD(scadFile: wrapperFile, outputFile: tempSTL)
            if extrudedResult.isEmpty {
                throw OpenSCADError.emptyFile(messages: result.messages)
            }

            let model = try STLParser.parse(url: tempSTL)
            var allMessages = result.messages
            allMessages.append(contentsOf: extrudedResult.messages)
            return ColoredRenderResult(model: model, warnings: allMessages, is2D: true, colorsExtracted: 0)
        }

        let model = try STLParser.parse(url: tempSTL)
        return ColoredRenderResult(model: model, warnings: result.messages, is2D: false, colorsExtracted: 0)
    }

    /// Convert a .scad file to .csg format
    private func convertToCSG(scadFile: URL, outputFile: URL) throws {
        let openscadPath = try findOpenSCADExecutable()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: openscadPath)
        process.arguments = ["-o", outputFile.path, scadFile.path]
        process.currentDirectoryURL = workDir

        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw OpenSCADError.renderFailed("CSG conversion failed: \(stderr)", messages: [])
        }
    }

    /// Extract all unique colors from a CSG file by running OpenSCAD with a redefined color() module
    private func extractColors(csgFile: URL, sessionId: String.SubSequence) throws -> Set<OpenSCADColor> {
        let openscadPath = try findOpenSCADExecutable()

        // Redefine color() to echo its parameters instead of rendering
        let colorExtractor = "module color(c, alpha) { echo(\(colorTag)=str(c)); }"

        // Use a temp file since OpenSCAD doesn't accept /dev/null
        let tempOutput = workDir.appendingPathComponent("gostl_\(sessionId)_colors.stl")
        defer { try? FileManager.default.removeItem(at: tempOutput) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: openscadPath)
        process.arguments = [
            "-D", colorExtractor,
            "-o", tempOutput.path,
            csgFile.path
        ]
        process.currentDirectoryURL = workDir

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        // Parse colors from stderr (ECHO statements go there)
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let combinedOutput = stderr + "\n" + stdout

        var colors = Set<OpenSCADColor>()

        // Look for ECHO: GOSTL_COLOR = "[r, g, b, a]"
        let pattern = "ECHO: \(colorTag) = \"(\\[[^\\]]+\\])\""
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = combinedOutput as NSString
            let matches = regex.matches(in: combinedOutput, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                if match.numberOfRanges >= 2 {
                    let colorRange = match.range(at: 1)
                    let colorString = nsString.substring(with: colorRange)
                    if let color = OpenSCADColor(fromOpenSCADString: colorString) {
                        colors.insert(color)
                    }
                }
            }
        }

        print("  Extracted colors: \(colors)")
        return colors
    }

    /// Check if the model has any geometry not wrapped in color()
    private func checkForUncoloredGeometry(csgFile: URL, sessionId: String.SubSequence) throws -> Bool {
        let openscadPath = try findOpenSCADExecutable()

        // Redefine color() to consume its children (output nothing)
        let colorDisabler = "module color(c, alpha) { /* discard */ }"

        let tempSTL = workDir.appendingPathComponent("gostl_\(sessionId)_uncolored.stl")
        defer { try? FileManager.default.removeItem(at: tempSTL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: openscadPath)
        process.arguments = [
            "-D", colorDisabler,
            "-o", tempSTL.path,
            csgFile.path
        ]
        process.currentDirectoryURL = workDir

        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        // Check if the output file has any geometry
        if FileManager.default.fileExists(atPath: tempSTL.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: tempSTL.path)
            let fileSize = attrs?[.size] as? Int ?? 0
            // Empty binary STL is 84 bytes (header + 0 triangles)
            return fileSize > 84
        }

        return false
    }

    /// Render each color separately and combine results
    /// - Parameters:
    ///   - csgFile: The CSG file to render
    ///   - colors: Array of colors to render
    ///   - includeUncolored: If true, also render geometry not wrapped in color() calls
    ///   - sessionId: Unique identifier for this render session
    private func renderColorsInParallel(csgFile: URL, colors: [OpenSCADColor], includeUncolored: Bool = false, sessionId: String.SubSequence) throws -> [Triangle] {
        let openscadPath = try findOpenSCADExecutable()

        // Thread-safe storage for results
        final class ColorResult: @unchecked Sendable {
            var triangles: [Triangle] = []
            var error: Error?
        }

        // Add one extra slot for uncolored geometry if needed
        let totalJobs = colors.count + (includeUncolored ? 1 : 0)
        let results = (0..<totalJobs).map { _ in ColorResult() }
        let localWorkDir = self.workDir  // Capture for Sendable closure
        let localSessionId = String(sessionId)  // Capture for Sendable closure

        // Render each color in parallel (plus uncolored if requested)
        DispatchQueue.concurrentPerform(iterations: totalJobs) { index in
            let tempSTL = localWorkDir.appendingPathComponent("gostl_\(localSessionId)_c\(index).stl")

            defer { try? FileManager.default.removeItem(at: tempSTL) }

            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: openscadPath)

                if index < colors.count {
                    // Render specific color
                    let color = colors[index]
                    let colorFilter = """
                    module color(c, alpha) {
                        if ($colored) {
                            children();
                        } else {
                            $colored = true;
                            if (str(c) == "\(color.openSCADString)") children();
                        }
                    }
                    """

                    process.arguments = [
                        "-D", "$colored = false;",
                        "-D", colorFilter,
                        "-o", tempSTL.path,
                        csgFile.path
                    ]
                } else {
                    // Render uncolored geometry (discard all color() children)
                    let colorDisabler = "module color(c, alpha) { /* discard colored geometry */ }"

                    process.arguments = [
                        "-D", colorDisabler,
                        "-o", tempSTL.path,
                        csgFile.path
                    ]
                }

                process.currentDirectoryURL = localWorkDir
                process.standardOutput = Pipe()
                process.standardError = Pipe()

                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: tempSTL.path) {
                    // Parse the STL
                    var model = try STLParser.parse(url: tempSTL)

                    if index < colors.count {
                        // Assign the specific color to all triangles
                        let triangleColor = colors[index].triangleColor
                        for i in 0..<model.triangles.count {
                            model.triangles[i].color = triangleColor
                        }
                    }
                    // For uncolored geometry, leave color as nil (will use material color)

                    results[index].triangles = model.triangles
                }
            } catch {
                results[index].error = error
            }
        }

        // Combine all triangles
        var allTriangles: [Triangle] = []
        for result in results {
            if let error = result.error {
                print("Warning: Color rendering failed: \(error)")
            }
            allTriangles.append(contentsOf: result.triangles)
        }

        return allTriangles
    }

    /// Extract warnings from running OpenSCAD on a file
    private func extractWarnings(csgFile: URL, sessionId: String.SubSequence) throws -> [String] {
        let openscadPath = try findOpenSCADExecutable()

        // Use a temp file since OpenSCAD doesn't accept /dev/null
        let tempOutput = workDir.appendingPathComponent("gostl_\(sessionId)_warn.stl")
        defer { try? FileManager.default.removeItem(at: tempOutput) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: openscadPath)
        process.arguments = ["-o", tempOutput.path, csgFile.path]
        process.currentDirectoryURL = workDir

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return parseMessages(stdout: stdout, stderr: stderr)
    }

    // MARK: - Standard Rendering

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

        // Use UUID to avoid conflicts when multiple files are rendered simultaneously
        let wrapperFile = workDir.appendingPathComponent("gostl_2d_\(UUID().uuidString.prefix(8)).scad")
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
