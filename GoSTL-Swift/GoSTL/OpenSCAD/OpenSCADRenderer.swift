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

    /// How to run OpenSCAD.
    ///
    /// Was a private function answering with a path, which every one of the
    /// eleven passes below turned into a `Process` of its own. See
    /// `OpenSCADCommand` for why that shape had to go: it can only ever mean a
    /// binary on this machine, and the embedder is the one that knows whether
    /// that is true.
    private let openSCAD: OpenSCADCommand

    /// Unique tag for color extraction
    private let colorTag = "GOSTL_COLOR"

    /// Initialize renderer with a working directory
    ///
    /// - Parameter openSCAD: defaulted, so every existing caller and a viewer
    ///   running on its own keep exactly the behaviour they had.
    init(workDir: URL, openSCAD: OpenSCADCommand = InstalledOpenSCAD()) {
        self.workDir = workDir
        self.openSCAD = openSCAD
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
    /// - Parameters:
    ///   - scadFile: The OpenSCAD source file
    ///   - outputFile: Where to write the CSG output
    ///   - runFromSourceDir: If true, run from the source file's directory to resolve relative imports correctly
    private func convertToCSG(scadFile: URL, outputFile: URL, runFromSourceDir: Bool = false) throws {
        let runDir = runFromSourceDir ? scadFile.deletingLastPathComponent() : workDir

        // Run from source directory when exporting, so relative imports resolve correctly
        let process = try openSCAD.makeProcess(
            arguments: ["-o", outputFile.path, scadFile.path],
            workingDirectory: runDir
        )

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
        // Redefine color() to echo its parameters instead of rendering
        let colorExtractor = "module color(c, alpha) { echo(\(colorTag)=str(c)); }"

        // Use a temp file since OpenSCAD doesn't accept /dev/null
        let tempOutput = workDir.appendingPathComponent("gostl_\(sessionId)_colors.stl")
        defer { try? FileManager.default.removeItem(at: tempOutput) }

        let process = try openSCAD.makeProcess(
            arguments: [
                "-D", colorExtractor,
                "-o", tempOutput.path,
                csgFile.path
            ],
            workingDirectory: workDir
        )

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

        return colors
    }

    /// Check if the model has any geometry not wrapped in color()
    private func checkForUncoloredGeometry(csgFile: URL, sessionId: String.SubSequence) throws -> Bool {
        // Redefine color() to consume its children (output nothing)
        let colorDisabler = "module color(c, alpha) { /* discard */ }"

        let tempSTL = workDir.appendingPathComponent("gostl_\(sessionId)_uncolored.stl")
        defer { try? FileManager.default.removeItem(at: tempSTL) }

        let process = try openSCAD.makeProcess(
            arguments: [
                "-D", colorDisabler,
                "-o", tempSTL.path,
                csgFile.path
            ],
            workingDirectory: workDir
        )

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

    /// Extract colors from a CSG file, running from the specified source directory
    /// This is needed to resolve relative paths in the CSG file
    private func extractColorsForExport(csgFile: URL, sourceDir: URL, sessionId: String.SubSequence) throws -> Set<OpenSCADColor> {
        // Redefine color() to echo its parameters instead of rendering
        let colorExtractor = "module color(c, alpha) { echo(\(colorTag)=str(c)); }"

        // Use a temp file since OpenSCAD doesn't accept /dev/null
        let tempOutput = workDir.appendingPathComponent("gostl_\(sessionId)_colors.stl")
        defer { try? FileManager.default.removeItem(at: tempOutput) }

        // Run from source directory to resolve relative imports in CSG
        let process = try openSCAD.makeProcess(
            arguments: [
                "-D", colorExtractor,
                "-o", tempOutput.path,
                csgFile.path
            ],
            workingDirectory: sourceDir
        )

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

        return colors
    }

    /// Check for uncolored geometry, running from the specified source directory
    private func checkForUncoloredGeometryForExport(csgFile: URL, sourceDir: URL, sessionId: String.SubSequence) throws -> Bool {
        // Redefine color() to consume its children (output nothing)
        let colorDisabler = "module color(c, alpha) { /* discard */ }"

        let tempSTL = workDir.appendingPathComponent("gostl_\(sessionId)_uncolored.stl")
        defer { try? FileManager.default.removeItem(at: tempSTL) }

        // Run from source directory to resolve relative imports in CSG
        let process = try openSCAD.makeProcess(
            arguments: [
                "-D", colorDisabler,
                "-o", tempSTL.path,
                csgFile.path
            ],
            workingDirectory: sourceDir
        )

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
        // Likewise: OpenSCADCommand is Sendable so that this closure may hold
        // one. It used to capture the resolved path instead, which was the same
        // trick for the same reason.
        let openSCAD = self.openSCAD

        // Render each color in parallel (plus uncolored if requested)
        DispatchQueue.concurrentPerform(iterations: totalJobs) { index in
            let tempSTL = localWorkDir.appendingPathComponent("gostl_\(localSessionId)_c\(index).stl")

            defer { try? FileManager.default.removeItem(at: tempSTL) }

            do {
                let arguments: [String]
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

                    arguments = [
                        "-D", "$colored = false;",
                        "-D", colorFilter,
                        "-o", tempSTL.path,
                        csgFile.path
                    ]
                } else {
                    // Render uncolored geometry (discard all color() children)
                    let colorDisabler = "module color(c, alpha) { /* discard colored geometry */ }"

                    arguments = [
                        "-D", colorDisabler,
                        "-o", tempSTL.path,
                        csgFile.path
                    ]
                }

                let process = try openSCAD.makeProcess(
                    arguments: arguments, workingDirectory: localWorkDir
                )
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
        // Use a temp file since OpenSCAD doesn't accept /dev/null
        let tempOutput = workDir.appendingPathComponent("gostl_\(sessionId)_warn.stl")
        defer { try? FileManager.default.removeItem(at: tempOutput) }

        let process = try openSCAD.makeProcess(
            arguments: ["-o", tempOutput.path, csgFile.path],
            workingDirectory: workDir
        )

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
        // Run openscad command
        let process = try openSCAD.makeProcess(
            arguments: [
                "-o", outputFile.path,
                scadFile.path
            ],
            workingDirectory: workDir
        )

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

    // MARK: - Multi-Color Export for go3mf

    /// Result of exporting for go3mf
    struct Go3mfExportResult {
        /// Directory containing the exported STL files
        let outputDir: URL
        /// List of (filename, color) pairs for each exported part
        let parts: [(filename: String, color: OpenSCADColor?)]
        /// True if model has multiple colors
        var isMultiColor: Bool { parts.count > 1 }
    }

    /// Export an OpenSCAD file as separate STL files for go3mf multi-color support
    /// Each color gets its own STL file that can be assigned a different filament
    /// - Parameter scadFile: URL of the .scad file to export
    /// - Returns: Go3mfExportResult with paths to exported STL files
    func exportForGo3mf(scadFile: URL) throws -> Go3mfExportResult {
        let sessionId = UUID().uuidString.prefix(8)
        let outputDir = workDir.appendingPathComponent("gostl_go3mf_\(sessionId)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Use the source file's directory as working directory to resolve relative imports
        let sourceDir = scadFile.deletingLastPathComponent()

        // Step 1: Convert to CSG format, running from source dir to resolve relative imports
        // Put CSG in source directory so relative paths in CSG resolve correctly
        let csgFile = sourceDir.appendingPathComponent("gostl_\(sessionId).csg")
        defer { try? FileManager.default.removeItem(at: csgFile) }

        do {
            try convertToCSG(scadFile: scadFile, outputFile: csgFile, runFromSourceDir: true)
        } catch {
            // If CSG conversion fails, export as single STL
            let singleSTL = outputDir.appendingPathComponent("model.stl")
            _ = try renderToSTL(scadFile: scadFile, outputFile: singleSTL)
            return Go3mfExportResult(outputDir: outputDir, parts: [("model.stl", nil)])
        }

        // Step 2: Extract colors (run from source dir to resolve relative paths in CSG)
        let colors = try extractColorsForExport(csgFile: csgFile, sourceDir: sourceDir, sessionId: sessionId)

        // If no colors found, export as single STL
        if colors.isEmpty {
            let singleSTL = outputDir.appendingPathComponent("model.stl")
            _ = try renderToSTL(scadFile: scadFile, outputFile: singleSTL)
            return Go3mfExportResult(outputDir: outputDir, parts: [("model.stl", nil)])
        }

        // Step 3: Check for uncolored geometry (run from source dir)
        let hasUncolored = try checkForUncoloredGeometryForExport(csgFile: csgFile, sourceDir: sourceDir, sessionId: sessionId)

        // Step 4: Export each color as separate STL
        var parts: [(String, OpenSCADColor?)] = []
        let colorArray = Array(colors)

        for (index, color) in colorArray.enumerated() {
            let filename = "color_\(index + 1).stl"
            let stlPath = outputDir.appendingPathComponent(filename)

            // Use the exact string format from extraction for matching
            let colorString = color.openSCADString

            let colorFilter = """
            module color(c, alpha) {
                if ($colored) {
                    children();
                } else {
                    $colored = true;
                    if (str(c) == "\(colorString)") children();
                }
            }
            """

            // Run from source directory to resolve relative imports in CSG
            let process = try openSCAD.makeProcess(
                arguments: [
                    "-D", "$colored = false;",
                    "-D", colorFilter,
                    "-o", stlPath.path,
                    csgFile.path
                ],
                workingDirectory: sourceDir
            )
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: stlPath.path) {
                // Check if file has geometry
                let attrs = try? FileManager.default.attributesOfItem(atPath: stlPath.path)
                let size = attrs?[.size] as? Int ?? 0
                if size > 84 {  // More than empty STL
                    parts.append((filename, color))
                }
            }
        }

        // Export uncolored geometry if present
        if hasUncolored {
            let filename = "uncolored.stl"
            let stlPath = outputDir.appendingPathComponent(filename)

            let colorDisabler = "module color(c, alpha) { /* discard */ }"

            // Run from source directory to resolve relative imports in CSG
            let process = try openSCAD.makeProcess(
                arguments: [
                    "-D", colorDisabler,
                    "-o", stlPath.path,
                    csgFile.path
                ],
                workingDirectory: sourceDir
            )
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: stlPath.path) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: stlPath.path)
                let size = attrs?[.size] as? Int ?? 0
                if size > 84 {
                    parts.append((filename, nil))
                }
            }
        }

        // If somehow no parts were exported, fall back to single STL
        if parts.isEmpty {
            let singleSTL = outputDir.appendingPathComponent("model.stl")
            _ = try renderToSTL(scadFile: scadFile, outputFile: singleSTL)
            return Go3mfExportResult(outputDir: outputDir, parts: [("model.stl", nil)])
        }

        return Go3mfExportResult(outputDir: outputDir, parts: parts)
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
            // The snapshot, named explicitly: the stable release on that page
            // is 2021.01 and is not what this renders against.
            return "OpenSCAD not found in PATH. Install the development snapshot "
                + "— brew install --cask openscad@snapshot — or download one from "
                + "https://openscad.org/downloads.html#snapshots"
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
