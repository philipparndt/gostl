import Foundation
import simd

/// Filament colors for go3mf (matching extruder colors)
private let filamentColors: [Int: TriangleColor] = [
    0: TriangleColor(1.0, 1.0, 1.0),      // Auto/default: White (uses material color)
    1: TriangleColor(1.0, 1.0, 1.0),      // Filament 1: White (uses material color)
    2: TriangleColor(0.4, 0.8, 1.0),      // Filament 2: Bright cyan/blue
    3: TriangleColor(1.0, 0.5, 0.5),      // Filament 3: Bright red/coral
    4: TriangleColor(0.5, 1.0, 0.5),      // Filament 4: Bright green
    5: TriangleColor(1.0, 0.9, 0.4),      // Filament 5: Bright yellow
]

/// Renderer for go3mf YAML configurations
class Go3mfRenderer {
    private let configURL: URL
    private let workDir: URL
    private let config: Go3mfConfig

    /// Initialize with a YAML config file URL
    init(configURL: URL) throws {
        self.configURL = configURL
        self.workDir = configURL.deletingLastPathComponent()
        self.config = try Go3mfConfigParser.parse(url: configURL)
    }

    /// Render all objects from the config into a single STLModel
    func render() throws -> STLModel {
        var allTriangles: [Triangle] = []

        // Track bounding boxes for object packing
        var currentX: Double = 0
        let packingDistance = config.packingDistance ?? 10.0

        for object in config.objects {
            let objectTriangles = try renderObject(object)

            if objectTriangles.isEmpty {
                continue
            }

            // Calculate bounding box of this object
            let bbox = calculateBoundingBox(triangles: objectTriangles)

            // Offset triangles to pack them side by side
            let offsetX = currentX - bbox.min.x
            let offsettedTriangles = objectTriangles.map { triangle -> Triangle in
                Triangle(
                    v1: Vector3(triangle.v1.x + offsetX, triangle.v1.y, triangle.v1.z),
                    v2: Vector3(triangle.v2.x + offsetX, triangle.v2.y, triangle.v2.z),
                    v3: Vector3(triangle.v3.x + offsetX, triangle.v3.y, triangle.v3.z),
                    normal: triangle.normal,
                    color: triangle.color
                )
            }

            allTriangles.append(contentsOf: offsettedTriangles)

            // Update currentX for next object
            let newBbox = calculateBoundingBox(triangles: offsettedTriangles)
            currentX = newBbox.max.x + packingDistance
        }

        return STLModel(triangles: allTriangles, name: configURL.deletingPathExtension().lastPathComponent)
    }

    /// Render a single object with all its parts
    private func renderObject(_ object: Go3mfObject) throws -> [Triangle] {
        var objectTriangles: [Triangle] = []

        // Write object-level config files
        if let configs = object.config {
            try writeConfigFiles(configs)
        }

        for part in object.parts {
            let partTriangles = try renderPart(part, objectConfig: object.config)
            objectTriangles.append(contentsOf: partTriangles)
        }

        // Normalize position if requested (default: true)
        let normalize = object.normalizePosition ?? true
        if normalize && !objectTriangles.isEmpty {
            objectTriangles = normalizeToGround(objectTriangles)
        }

        return objectTriangles
    }

    /// Render a single part
    private func renderPart(_ part: Go3mfPart, objectConfig: [[String: String]]?) throws -> [Triangle] {
        // Write part-level config files (these override object-level)
        if let configs = part.config {
            try writeConfigFiles(configs)
        }

        // Resolve file path relative to config file
        let filePath = resolveFilePath(part.file)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw Go3mfConfigError.missingFile(part.file)
        }

        // Load the model based on file type
        var triangles = try loadModel(from: filePath)

        // Apply filament color
        let filament = part.filament ?? 0
        let color = filamentColors[filament] ?? filamentColors[0]!
        triangles = triangles.map { triangle in
            Triangle(
                v1: triangle.v1,
                v2: triangle.v2,
                v3: triangle.v3,
                normal: triangle.normal,
                color: color
            )
        }

        // Apply rotations (order: Z, Y, X)
        if let rz = part.rotationZ, rz != 0 {
            triangles = rotateTriangles(triangles, angle: rz, axis: .z)
        }
        if let ry = part.rotationY, ry != 0 {
            triangles = rotateTriangles(triangles, angle: ry, axis: .y)
        }
        if let rx = part.rotationX, rx != 0 {
            triangles = rotateTriangles(triangles, angle: rx, axis: .x)
        }

        // Apply position offset
        let offsetX = part.positionX ?? 0
        let offsetY = part.positionY ?? 0
        let offsetZ = part.positionZ ?? 0

        if offsetX != 0 || offsetY != 0 || offsetZ != 0 {
            triangles = triangles.map { triangle in
                Triangle(
                    v1: Vector3(triangle.v1.x + offsetX, triangle.v1.y + offsetY, triangle.v1.z + offsetZ),
                    v2: Vector3(triangle.v2.x + offsetX, triangle.v2.y + offsetY, triangle.v2.z + offsetZ),
                    v3: Vector3(triangle.v3.x + offsetX, triangle.v3.y + offsetY, triangle.v3.z + offsetZ),
                    normal: triangle.normal,
                    color: triangle.color
                )
            }
        }

        return triangles
    }

    /// Load a model from a file (STL, 3MF, or SCAD)
    private func loadModel(from url: URL) throws -> [Triangle] {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "stl":
            let model = try STLParser.parse(url: url)
            return model.triangles

        case "3mf":
            let model = try ThreeMFParser.parse(url: url)
            return model.triangles

        case "scad":
            return try renderOpenSCAD(url)

        default:
            throw Go3mfConfigError.unsupportedFileType(ext)
        }
    }

    /// Render an OpenSCAD file to triangles
    private func renderOpenSCAD(_ scadURL: URL) throws -> [Triangle] {
        let renderer = OpenSCADRenderer(workDir: workDir)

        // Create temporary STL file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("go3mf_temp_\(UUID().uuidString).stl")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try renderer.renderToSTL(scadFile: scadURL, outputFile: tempURL)

        let model = try STLParser.parse(url: tempURL)
        return model.triangles
    }

    /// Write config files to the working directory
    private func writeConfigFiles(_ configs: [[String: String]]) throws {
        for configMap in configs {
            for (filename, content) in configMap {
                let fileURL = workDir.appendingPathComponent(filename)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Resolve a file path relative to the config file
    private func resolveFilePath(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return workDir.appendingPathComponent(path)
    }

    /// Calculate bounding box of triangles
    private func calculateBoundingBox(triangles: [Triangle]) -> (min: Vector3, max: Vector3) {
        guard let first = triangles.first else {
            return (Vector3(0, 0, 0), Vector3(0, 0, 0))
        }

        var minV = first.v1
        var maxV = first.v1

        for triangle in triangles {
            for v in [triangle.v1, triangle.v2, triangle.v3] {
                minV = Vector3(min(minV.x, v.x), min(minV.y, v.y), min(minV.z, v.z))
                maxV = Vector3(max(maxV.x, v.x), max(maxV.y, v.y), max(maxV.z, v.z))
            }
        }

        return (minV, maxV)
    }

    /// Normalize triangles to sit on the ground (z=0)
    private func normalizeToGround(_ triangles: [Triangle]) -> [Triangle] {
        let bbox = calculateBoundingBox(triangles: triangles)
        let offsetZ = -bbox.min.z

        if offsetZ == 0 {
            return triangles
        }

        return triangles.map { triangle in
            Triangle(
                v1: Vector3(triangle.v1.x, triangle.v1.y, triangle.v1.z + offsetZ),
                v2: Vector3(triangle.v2.x, triangle.v2.y, triangle.v2.z + offsetZ),
                v3: Vector3(triangle.v3.x, triangle.v3.y, triangle.v3.z + offsetZ),
                normal: triangle.normal,
                color: triangle.color
            )
        }
    }

    /// Rotation axis
    private enum Axis {
        case x, y, z
    }

    /// Rotate triangles around an axis
    private func rotateTriangles(_ triangles: [Triangle], angle: Double, axis: Axis) -> [Triangle] {
        let radians = angle * .pi / 180.0
        let cosA = cos(radians)
        let sinA = sin(radians)

        func rotatePoint(_ p: Vector3) -> Vector3 {
            switch axis {
            case .x:
                return Vector3(p.x, p.y * cosA - p.z * sinA, p.y * sinA + p.z * cosA)
            case .y:
                return Vector3(p.x * cosA + p.z * sinA, p.y, -p.x * sinA + p.z * cosA)
            case .z:
                return Vector3(p.x * cosA - p.y * sinA, p.x * sinA + p.y * cosA, p.z)
            }
        }

        return triangles.map { triangle in
            Triangle(
                v1: rotatePoint(triangle.v1),
                v2: rotatePoint(triangle.v2),
                v3: rotatePoint(triangle.v3),
                normal: nil,  // Recalculate normal
                color: triangle.color
            )
        }
    }

    /// Get all file dependencies for file watching
    func getDependencies() -> [URL] {
        var deps = Set<URL>()
        deps.insert(configURL)

        // Collect config file names that are written during rendering (should not be watched)
        var generatedConfigFiles = Set<String>()
        for object in config.objects {
            if let configs = object.config {
                for configMap in configs {
                    for filename in configMap.keys {
                        generatedConfigFiles.insert(filename.lowercased())
                    }
                }
            }
            for part in object.parts {
                if let configs = part.config {
                    for configMap in configs {
                        for filename in configMap.keys {
                            generatedConfigFiles.insert(filename.lowercased())
                        }
                    }
                }
            }
        }

        for object in config.objects {
            for part in object.parts {
                let filePath = resolveFilePath(part.file)
                deps.insert(filePath)

                // For SCAD files, also resolve their dependencies
                if filePath.pathExtension.lowercased() == "scad" {
                    if let scadDeps = try? OpenSCADRenderer(workDir: workDir).resolveDependencies(scadFile: filePath) {
                        for dep in scadDeps {
                            // Exclude generated config files
                            let filename = dep.lastPathComponent.lowercased()
                            if !generatedConfigFiles.contains(filename) {
                                deps.insert(dep)
                            }
                        }
                    }
                }
            }
        }

        return Array(deps)
    }
}
