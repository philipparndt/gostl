import Foundation
import Compression

/// Build plate information from a 3MF file
struct ThreeMFPlate: Identifiable {
    let id: Int
    let name: String
    let objectIds: [Int]
    let thumbnailPath: String?
}

/// Result of parsing a 3MF file with plate support
struct ThreeMFParseResult {
    let plates: [ThreeMFPlate]
    let trianglesByPlate: [Int: [Triangle]]  // Plate ID -> triangles
    let allTriangles: [Triangle]
    let name: String?

    /// Get triangles for a specific plate
    func triangles(forPlate plateId: Int) -> [Triangle] {
        return trianglesByPlate[plateId] ?? []
    }

    /// Create an STLModel for a specific plate, centered at the origin
    func model(forPlate plateId: Int) -> STLModel {
        let tris = triangles(forPlate: plateId)
        let plateName = plates.first { $0.id == plateId }?.name
        let modelName = plateName.map { "\(name ?? "Model") - \($0)" } ?? name

        // Center the model at the origin (each plate may have different world-space positions)
        let centeredTris = centerTriangles(tris)
        return STLModel(triangles: centeredTris, name: modelName)
    }

    /// Center triangles around the origin based on their bounding box center
    private func centerTriangles(_ triangles: [Triangle]) -> [Triangle] {
        guard !triangles.isEmpty else { return triangles }

        // Calculate bounding box
        var minX = Double.infinity, minY = Double.infinity, minZ = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity, maxZ = -Double.infinity

        for tri in triangles {
            for v in [tri.v1, tri.v2, tri.v3] {
                minX = min(minX, v.x)
                minY = min(minY, v.y)
                minZ = min(minZ, v.z)
                maxX = max(maxX, v.x)
                maxY = max(maxY, v.y)
                maxZ = max(maxZ, v.z)
            }
        }

        // Calculate center offset (only X and Y, keep Z base at 0)
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let baseZ = minZ  // Move to Z=0 base

        // Translate all triangles
        return triangles.map { tri in
            Triangle(
                v1: Vector3(tri.v1.x - centerX, tri.v1.y - centerY, tri.v1.z - baseZ),
                v2: Vector3(tri.v2.x - centerX, tri.v2.y - centerY, tri.v2.z - baseZ),
                v3: Vector3(tri.v3.x - centerX, tri.v3.y - centerY, tri.v3.z - baseZ),
                normal: tri.normal,
                color: tri.color
            )
        }
    }

    /// Create an STLModel with all triangles
    func modelWithAllPlates() -> STLModel {
        return STLModel(triangles: allTriangles, name: name)
    }
}

/// Parser for 3MF files (3D Manufacturing Format)
/// 3MF files are ZIP archives containing XML model data
enum ThreeMFParser {

    // MARK: - Public API

    /// Parse a 3MF file from a URL
    static func parse(url: URL) throws -> STLModel {
        let result = try parseWithPlates(url: url)
        // If there's only one plate, return it; otherwise return all triangles
        if result.plates.count == 1, let plate = result.plates.first {
            return result.model(forPlate: plate.id)
        }
        return result.modelWithAllPlates()
    }

    /// Parse a 3MF file with plate support
    static func parseWithPlates(url: URL) throws -> ThreeMFParseResult {
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        return try parseWithPlates(data: data, name: name)
    }

    /// Parse 3MF data
    static func parse(data: Data, name: String? = nil) throws -> STLModel {
        let result = try parseWithPlates(data: data, name: name)
        if result.plates.count == 1, let plate = result.plates.first {
            return result.model(forPlate: plate.id)
        }
        return result.modelWithAllPlates()
    }

    /// Parse 3MF data with plate support
    static func parseWithPlates(data: Data, name: String? = nil) throws -> ThreeMFParseResult {
        // 3MF is a ZIP archive - extract and parse
        var archive = try ZipArchive(data: data)

        // Find the 3D model file (usually 3D/3dmodel.model)
        guard let modelData = try archive.findModelFile() else {
            throw ThreeMFError.modelFileNotFound
        }

        // First, parse plate and color info from model_settings.config
        let (plates, partExtruders) = parsePlateAndColorInfo(archive: archive)
        print("Found \(plates.count) plates in 3MF file")
        for plate in plates {
            print("  Plate \(plate.id): \(plate.name) with objects: \(plate.objectIds)")
        }
        print("Found \(partExtruders.count) part extruder assignments")
        for (objId, parts) in partExtruders {
            print("  Object \(objId): \(parts)")
        }

        // Parse the XML model (pass archive and part extruders for color resolution)
        let parser = ThreeMFXMLParser(data: modelData, archive: archive, partExtruders: partExtruders)
        let (allTriangles, trianglesByObjectId) = try parser.parseWithObjectMapping()
        archive = parser.archive

        // Use the parsed triangles with colors already applied
        let coloredTrianglesByObjectId = trianglesByObjectId

        // Build triangles by plate
        var trianglesByPlate: [Int: [Triangle]] = [:]
        for plate in plates {
            var plateTriangles: [Triangle] = []
            for objectId in plate.objectIds {
                if let tris = coloredTrianglesByObjectId[objectId] {
                    plateTriangles.append(contentsOf: tris)
                }
            }
            trianglesByPlate[plate.id] = plateTriangles
        }

        // If no plates found, create a single "All Objects" plate
        let finalPlates: [ThreeMFPlate]
        if plates.isEmpty {
            finalPlates = [ThreeMFPlate(id: 1, name: "All Objects", objectIds: [], thumbnailPath: nil)]
            trianglesByPlate[1] = allTriangles
        } else {
            finalPlates = plates
        }

        return ThreeMFParseResult(
            plates: finalPlates,
            trianglesByPlate: trianglesByPlate,
            allTriangles: allTriangles,
            name: name
        )
    }

    // MARK: - Plate and Color Parsing

    /// Part extruder assignment: maps (objectId, partId) -> extruder number
    typealias PartExtruderMap = [Int: [Int: Int]]  // objectId -> (partId -> extruder)

    private static func parsePlateAndColorInfo(archive: ZipArchive) -> (plates: [ThreeMFPlate], partExtruders: PartExtruderMap) {
        // Try to extract model_settings.config
        guard let configData = try? archive.extractFile(path: "Metadata/model_settings.config") else {
            return ([], [:])
        }

        let parser = PlateConfigParser(data: configData)
        return (try? parser.parseWithColors()) ?? ([], [:])
    }

}

// MARK: - 3x4 Transform Matrix (row-major: m00 m01 m02 m03 m10 m11 m12 m13 m20 m21 m22 m23)
// The last column (m03, m13, m23) is the translation

private struct Transform3D {
    var m: [Double]  // 12 elements: 3 rows x 4 columns

    static let identity = Transform3D(m: [1, 0, 0, 0,
                                          0, 1, 0, 0,
                                          0, 0, 1, 0])

    /// Parse transform from 3MF format: "m00 m01 m02 m10 m11 m12 m20 m21 m22 m03 m13 m23"
    /// Note: 3MF stores rotation first (9 values), then translation (3 values)
    init?(from string: String) {
        let parts = string.split(separator: " ").compactMap { Double($0) }
        guard parts.count == 12 else { return nil }

        // 3MF format: m00 m01 m02 m10 m11 m12 m20 m21 m22 tx ty tz
        // Convert to row-major with translation in last column
        m = [
            parts[0], parts[1], parts[2], parts[9],   // row 0
            parts[3], parts[4], parts[5], parts[10],  // row 1
            parts[6], parts[7], parts[8], parts[11]   // row 2
        ]
    }

    init(m: [Double]) {
        self.m = m
    }

    /// Apply transform to a point
    func apply(to point: Vector3) -> Vector3 {
        let x = m[0] * point.x + m[1] * point.y + m[2] * point.z + m[3]
        let y = m[4] * point.x + m[5] * point.y + m[6] * point.z + m[7]
        let z = m[8] * point.x + m[9] * point.y + m[10] * point.z + m[11]
        return Vector3(x, y, z)
    }

    /// Multiply two transforms: self * other
    func multiply(_ other: Transform3D) -> Transform3D {
        var result = [Double](repeating: 0, count: 12)

        for row in 0..<3 {
            for col in 0..<4 {
                var sum = 0.0
                for k in 0..<3 {
                    sum += m[row * 4 + k] * other.m[k * 4 + col]
                }
                // Add translation component for the last column
                if col == 3 {
                    sum += m[row * 4 + 3]
                }
                result[row * 4 + col] = sum
            }
        }

        return Transform3D(m: result)
    }
}

// MARK: - Extruder Colors

private let extruderColors: [Int: TriangleColor] = [
    1: TriangleColor(0.8, 0.8, 0.8),      // Extruder 1: Light gray
    2: TriangleColor(0.2, 0.6, 0.9),      // Extruder 2: Blue
    3: TriangleColor(0.9, 0.3, 0.3),      // Extruder 3: Red
    4: TriangleColor(0.3, 0.8, 0.3),      // Extruder 4: Green
    5: TriangleColor(0.9, 0.7, 0.2),      // Extruder 5: Yellow/Orange
]

// MARK: - 3MF Object (mesh or component assembly)

private struct ThreeMFObject {
    let id: Int
    var pid: Int?  // Property ID (extruder/material)
    var triangles: [Triangle] = []
    var components: [(objectId: Int, path: String?, transform: Transform3D)] = []
}

// MARK: - Build Item

private struct BuildItem {
    let objectId: Int
    let transform: Transform3D
}

// MARK: - XML Parser

private class ThreeMFXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private(set) var archive: ZipArchive
    private var parseError: Error?

    // Part extruder assignments from model_settings.config
    private let partExtruders: [Int: [Int: Int]]

    // Objects by ID (includes both local and external objects)
    private var objects: [Int: ThreeMFObject] = [:]
    // Objects loaded from external files, keyed by (path, objectId)
    private var externalObjects: [String: [Int: ThreeMFObject]] = [:]
    private var buildItems: [BuildItem] = []
    // External paths to load after main parsing completes (to avoid reentrant parsing)
    private var pendingExternalPaths: Set<String> = []

    // Current parsing state
    private var currentObjectId: Int?
    private var vertices: [Vector3] = []
    private var inMesh = false
    private var inVertices = false
    private var inTriangles = false
    private var inComponents = false
    private var inBuild = false

    init(data: Data, archive: ZipArchive, partExtruders: [Int: [Int: Int]] = [:]) {
        self.data = data
        self.archive = archive
        self.partExtruders = partExtruders
    }

    func parse() throws -> [Triangle] {
        let (triangles, _) = try parseWithObjectMapping()
        return triangles
    }

    /// Parse and return both all triangles and a mapping of objectId -> triangles
    func parseWithObjectMapping() throws -> (allTriangles: [Triangle], trianglesByObjectId: [Int: [Triangle]]) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true

        guard parser.parse() else {
            if let error = parseError {
                throw error
            }
            throw ThreeMFError.xmlParsingFailed
        }

        // Load external models that were referenced during parsing
        // (deferred to avoid reentrant XML parsing)
        loadPendingExternalModels()

        // Build final triangles by processing build items
        return buildFinalMeshWithObjectMapping()
    }

    /// Recursively collect triangles from an object, applying transforms
    /// - parentObjectId: The top-level object ID from the main model (used for extruder lookup)
    /// - objectId: The current object ID being processed
    /// - path: Path to external model file if this is an external component
    /// - transform: Accumulated transformation matrix
    /// - inheritedPid: Inherited property ID from parent
    private func collectTriangles(parentObjectId: Int? = nil, objectId: Int, path: String? = nil, transform: Transform3D, inheritedPid: Int? = nil) -> [Triangle] {
        // Look up object from external file or local objects
        let obj: ThreeMFObject?
        if let path = path, let externalObjs = externalObjects[path] {
            obj = externalObjs[objectId]
        } else {
            obj = objects[objectId]
        }

        guard let obj = obj else { return [] }

        var result: [Triangle] = []

        // Determine the effective extruder/color:
        // 1. Check if there's a part-specific extruder in model_settings.config
        // 2. Fall back to object's pid
        // 3. Fall back to inherited pid
        let lookupObjectId = parentObjectId ?? objectId
        var effectivePid = obj.pid ?? inheritedPid

        // Check for part-specific extruder from model_settings.config
        if let objectExtruders = partExtruders[lookupObjectId] {
            // First check if this specific part (objectId) has an extruder assigned
            if let partExtruder = objectExtruders[objectId] {
                effectivePid = partExtruder
            }
            // Also check the parent object's default extruder
            else if effectivePid == nil, let defaultExtruder = objectExtruders[lookupObjectId] {
                effectivePid = defaultExtruder
            }
        }

        let color = effectivePid.flatMap { extruderColors[$0] }

        // Add this object's triangles with transform and color applied
        for triangle in obj.triangles {
            let v1 = transform.apply(to: triangle.v1)
            let v2 = transform.apply(to: triangle.v2)
            let v3 = transform.apply(to: triangle.v3)
            // Use triangle's existing color if set, otherwise use object's color
            let triangleColor = triangle.color ?? color
            result.append(Triangle(v1: v1, v2: v2, v3: v3, normal: nil, color: triangleColor))
        }

        // Recursively process components, passing down the parent object ID and pid
        for component in obj.components {
            let combinedTransform = transform.multiply(component.transform)
            // Keep track of the top-level parent for extruder lookup
            let effectiveParent = parentObjectId ?? objectId
            result.append(contentsOf: collectTriangles(parentObjectId: effectiveParent, objectId: component.objectId, path: component.path, transform: combinedTransform, inheritedPid: effectivePid))
        }

        return result
    }

    /// Build the final mesh from build items
    private func buildFinalMesh() -> [Triangle] {
        let (triangles, _) = buildFinalMeshWithObjectMapping()
        return triangles
    }

    /// Build the final mesh and return a mapping of objectId -> triangles
    private func buildFinalMeshWithObjectMapping() -> (allTriangles: [Triangle], trianglesByObjectId: [Int: [Triangle]]) {
        var allTriangles: [Triangle] = []
        var trianglesByObjectId: [Int: [Triangle]] = [:]

        if buildItems.isEmpty {
            // No build section - just collect all object triangles directly
            for (id, obj) in objects {
                if !obj.triangles.isEmpty {
                    allTriangles.append(contentsOf: obj.triangles)
                    trianglesByObjectId[id] = obj.triangles
                }
            }
        } else {
            // Process build items with transforms
            for item in buildItems {
                let itemTriangles = collectTriangles(objectId: item.objectId, transform: item.transform)
                allTriangles.append(contentsOf: itemTriangles)
                trianglesByObjectId[item.objectId] = itemTriangles
            }
        }

        return (allTriangles, trianglesByObjectId)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName.lowercased() {
        case "object":
            if let idStr = attributeDict["id"], let id = Int(idStr) {
                currentObjectId = id
                let pid = attributeDict["pid"].flatMap { Int($0) }
                objects[id] = ThreeMFObject(id: id, pid: pid)
            }

        case "mesh":
            inMesh = true
            vertices.removeAll()

        case "vertices":
            if inMesh {
                inVertices = true
            }

        case "vertex":
            if inVertices {
                parseVertex(attributes: attributeDict)
            }

        case "triangles":
            if inMesh {
                inTriangles = true
            }

        case "triangle":
            if inTriangles, let objectId = currentObjectId {
                parseTriangle(attributes: attributeDict, objectId: objectId)
            }

        case "components":
            inComponents = true

        case "component":
            if inComponents, let objectId = currentObjectId {
                parseComponent(attributes: attributeDict, parentObjectId: objectId)
            }

        case "build":
            inBuild = true

        case "item":
            if inBuild {
                parseBuildItem(attributes: attributeDict)
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName.lowercased() {
        case "object":
            currentObjectId = nil
        case "mesh":
            inMesh = false
        case "vertices":
            inVertices = false
        case "triangles":
            inTriangles = false
        case "components":
            inComponents = false
        case "build":
            inBuild = false
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    // MARK: - Element Parsing

    private func parseVertex(attributes: [String: String]) {
        guard let xStr = attributes["x"], let x = Double(xStr),
              let yStr = attributes["y"], let y = Double(yStr),
              let zStr = attributes["z"], let z = Double(zStr) else {
            return
        }
        vertices.append(Vector3(x, y, z))
    }

    private func parseTriangle(attributes: [String: String], objectId: Int) {
        guard let v1Str = attributes["v1"], let v1Idx = Int(v1Str),
              let v2Str = attributes["v2"], let v2Idx = Int(v2Str),
              let v3Str = attributes["v3"], let v3Idx = Int(v3Str) else {
            return
        }

        guard v1Idx >= 0 && v1Idx < vertices.count,
              v2Idx >= 0 && v2Idx < vertices.count,
              v3Idx >= 0 && v3Idx < vertices.count else {
            return
        }

        let triangle = Triangle(
            v1: vertices[v1Idx],
            v2: vertices[v2Idx],
            v3: vertices[v3Idx],
            normal: nil
        )

        objects[objectId]?.triangles.append(triangle)
    }

    private func parseComponent(attributes: [String: String], parentObjectId: Int) {
        guard let objectIdStr = attributes["objectid"], let objectId = Int(objectIdStr) else {
            return
        }

        let transform: Transform3D
        if let transformStr = attributes["transform"], let t = Transform3D(from: transformStr) {
            transform = t
        } else {
            transform = .identity
        }

        // Check for external path (p:path attribute)
        // Try both with and without namespace prefix
        let path = attributes["p:path"] ?? attributes["path"]

        // Record the path for later loading (can't load during XML parsing due to reentrant parsing restriction)
        if let path = path {
            pendingExternalPaths.insert(path)
        }

        objects[parentObjectId]?.components.append((objectId: objectId, path: path, transform: transform))
    }

    /// Load all pending external model files from the archive (called after main parsing completes)
    private func loadPendingExternalModels() {
        for path in pendingExternalPaths {
            loadExternalModel(path: path)
        }
        pendingExternalPaths.removeAll()
    }

    /// Load an external model file from the archive
    private func loadExternalModel(path: String) {
        // Skip if already loaded
        if externalObjects[path] != nil {
            return
        }

        // Normalize path (remove leading slash if present)
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path

        // Try to extract the file from the archive
        guard let modelData = try? archive.extractFile(path: normalizedPath) else {
            print("Warning: Could not load external model: \(path)")
            return
        }

        // Parse the external model file
        let parser = ExternalModelParser(data: modelData)
        if let objects = try? parser.parse() {
            externalObjects[path] = objects
        }
    }

    private func parseBuildItem(attributes: [String: String]) {
        guard let objectIdStr = attributes["objectid"], let objectId = Int(objectIdStr) else {
            return
        }

        let transform: Transform3D
        if let transformStr = attributes["transform"], let t = Transform3D(from: transformStr) {
            transform = t
        } else {
            transform = .identity
        }

        buildItems.append(BuildItem(objectId: objectId, transform: transform))
    }
}

// MARK: - Plate Config Parser (for model_settings.config)

private class PlateConfigParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var parseError: Error?

    // Parsed plates
    private var plates: [ThreeMFPlate] = []

    // Part extruder assignments: objectId -> (partId -> extruder)
    private var partExtruders: [Int: [Int: Int]] = [:]

    // Current parsing state
    private var inPlate = false
    private var inModelInstance = false
    private var inObject = false
    private var inPart = false
    private var currentPlateId: Int?
    private var currentPlateName: String?
    private var currentThumbnailPath: String?
    private var currentObjectIds: [Int] = []

    // Object/part tracking for extruder assignments
    private var currentObjectId: Int?
    private var currentObjectExtruder: Int?
    private var currentPartId: Int?
    private var currentPartExtruder: Int?

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> [ThreeMFPlate] {
        let (plates, _) = try parseWithColors()
        return plates
    }

    func parseWithColors() throws -> (plates: [ThreeMFPlate], partExtruders: [Int: [Int: Int]]) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false

        guard parser.parse() else {
            if let error = parseError {
                throw error
            }
            throw ThreeMFError.xmlParsingFailed
        }

        return (plates, partExtruders)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        switch elementName.lowercased() {
        case "plate":
            inPlate = true
            currentPlateId = nil
            currentPlateName = nil
            currentThumbnailPath = nil
            currentObjectIds = []

        case "model_instance":
            if inPlate {
                inModelInstance = true
            }

        case "object":
            // Object definition (outside plate)
            if !inPlate {
                inObject = true
                if let idStr = attributeDict["id"], let id = Int(idStr) {
                    currentObjectId = id
                    currentObjectExtruder = nil
                }
            }

        case "part":
            // Part definition inside object
            if inObject {
                inPart = true
                if let idStr = attributeDict["id"], let id = Int(idStr) {
                    currentPartId = id
                    currentPartExtruder = nil
                }
            }

        case "metadata":
            let key = attributeDict["key"]
            let value = attributeDict["value"]

            if inPlate {
                if inModelInstance {
                    // Inside model_instance, look for object_id
                    if key == "object_id", let value = value, let objId = Int(value) {
                        currentObjectIds.append(objId)
                    }
                } else {
                    // Plate-level metadata
                    switch key {
                    case "plater_id":
                        if let value = value {
                            currentPlateId = Int(value)
                        }
                    case "plater_name":
                        currentPlateName = value
                    case "thumbnail_file":
                        currentThumbnailPath = value
                    default:
                        break
                    }
                }
            } else if inObject {
                // Object or part extruder assignment
                if key == "extruder", let value = value, let extruder = Int(value) {
                    if inPart {
                        currentPartExtruder = extruder
                    } else {
                        currentObjectExtruder = extruder
                    }
                }
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName.lowercased() {
        case "plate":
            // Save the plate if we have valid data
            if let plateId = currentPlateId, let plateName = currentPlateName {
                let plate = ThreeMFPlate(
                    id: plateId,
                    name: plateName,
                    objectIds: currentObjectIds,
                    thumbnailPath: currentThumbnailPath
                )
                plates.append(plate)
            }
            inPlate = false

        case "model_instance":
            inModelInstance = false

        case "object":
            // Save object extruder assignment
            if let objectId = currentObjectId {
                if partExtruders[objectId] == nil {
                    partExtruders[objectId] = [:]
                }
                // Store object-level extruder as self-reference
                if let extruder = currentObjectExtruder {
                    partExtruders[objectId]![objectId] = extruder
                }
            }
            inObject = false
            currentObjectId = nil
            currentObjectExtruder = nil

        case "part":
            // Save part extruder assignment
            if let objectId = currentObjectId, let partId = currentPartId, let extruder = currentPartExtruder {
                if partExtruders[objectId] == nil {
                    partExtruders[objectId] = [:]
                }
                partExtruders[objectId]![partId] = extruder
            }
            inPart = false
            currentPartId = nil
            currentPartExtruder = nil

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}

// MARK: - External Model Parser (for loading referenced model files)

private class ExternalModelParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var parseError: Error?

    // Objects parsed from this file
    private var objects: [Int: ThreeMFObject] = [:]

    // Current parsing state
    private var currentObjectId: Int?
    private var vertices: [Vector3] = []
    private var inMesh = false
    private var inVertices = false
    private var inTriangles = false

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> [Int: ThreeMFObject] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true

        guard parser.parse() else {
            if let error = parseError {
                throw error
            }
            throw ThreeMFError.xmlParsingFailed
        }

        return objects
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName.lowercased() {
        case "object":
            if let idStr = attributeDict["id"], let id = Int(idStr) {
                currentObjectId = id
                let pid = attributeDict["pid"].flatMap { Int($0) }
                objects[id] = ThreeMFObject(id: id, pid: pid)
            }

        case "mesh":
            inMesh = true
            vertices.removeAll()

        case "vertices":
            if inMesh {
                inVertices = true
            }

        case "vertex":
            if inVertices {
                parseVertex(attributes: attributeDict)
            }

        case "triangles":
            if inMesh {
                inTriangles = true
            }

        case "triangle":
            if inTriangles, let objectId = currentObjectId {
                parseTriangle(attributes: attributeDict, objectId: objectId)
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName.lowercased() {
        case "object":
            currentObjectId = nil
        case "mesh":
            inMesh = false
        case "vertices":
            inVertices = false
        case "triangles":
            inTriangles = false
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    // MARK: - Element Parsing

    private func parseVertex(attributes: [String: String]) {
        guard let xStr = attributes["x"], let x = Double(xStr),
              let yStr = attributes["y"], let y = Double(yStr),
              let zStr = attributes["z"], let z = Double(zStr) else {
            return
        }
        vertices.append(Vector3(x, y, z))
    }

    private func parseTriangle(attributes: [String: String], objectId: Int) {
        guard let v1Str = attributes["v1"], let v1Idx = Int(v1Str),
              let v2Str = attributes["v2"], let v2Idx = Int(v2Str),
              let v3Str = attributes["v3"], let v3Idx = Int(v3Str) else {
            return
        }

        guard v1Idx >= 0 && v1Idx < vertices.count,
              v2Idx >= 0 && v2Idx < vertices.count,
              v3Idx >= 0 && v3Idx < vertices.count else {
            return
        }

        let triangle = Triangle(
            v1: vertices[v1Idx],
            v2: vertices[v2Idx],
            v3: vertices[v3Idx],
            normal: nil
        )

        objects[objectId]?.triangles.append(triangle)
    }
}

// MARK: - ZIP Archive Reader

private struct ZipArchive {
    private let data: Data
    private var entries: [ZipEntry] = []

    struct ZipEntry {
        let filename: String
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let compressionMethod: UInt16
        let localHeaderOffset: UInt32
    }

    init(data: Data) throws {
        self.data = data

        guard data.count >= 4 else {
            throw ThreeMFError.invalidZipFormat
        }

        let signature = data.prefix(4)
        guard signature[0] == 0x50 && signature[1] == 0x4B &&
              signature[2] == 0x03 && signature[3] == 0x04 else {
            throw ThreeMFError.invalidZipFormat
        }

        try parseCentralDirectory()
    }

    private mutating func parseCentralDirectory() throws {
        var eocdOffset = -1
        let minEOCDSize = 22

        for i in stride(from: data.count - minEOCDSize, through: max(0, data.count - 65557), by: -1) {
            if data[i] == 0x50 && data[i + 1] == 0x4B &&
               data[i + 2] == 0x05 && data[i + 3] == 0x06 {
                eocdOffset = i
                break
            }
        }

        guard eocdOffset >= 0 else {
            throw ThreeMFError.invalidZipFormat
        }

        let centralDirOffset = readUInt32(at: eocdOffset + 16)
        var offset = Int(centralDirOffset)

        while offset + 46 < data.count {
            guard data[offset] == 0x50 && data[offset + 1] == 0x4B &&
                  data[offset + 2] == 0x01 && data[offset + 3] == 0x02 else {
                break
            }

            let compressionMethod = readUInt16(at: offset + 10)
            let compressedSize = readUInt32(at: offset + 20)
            let uncompressedSize = readUInt32(at: offset + 24)
            let filenameLength = readUInt16(at: offset + 28)
            let extraLength = readUInt16(at: offset + 30)
            let commentLength = readUInt16(at: offset + 32)
            let localHeaderOffset = readUInt32(at: offset + 42)

            let filenameStart = offset + 46
            let filenameEnd = filenameStart + Int(filenameLength)

            guard filenameEnd <= data.count else { break }

            let filenameData = data[filenameStart..<filenameEnd]
            let filename = String(data: filenameData, encoding: .utf8) ?? ""

            entries.append(ZipEntry(
                filename: filename,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                compressionMethod: compressionMethod,
                localHeaderOffset: localHeaderOffset
            ))

            offset = filenameEnd + Int(extraLength) + Int(commentLength)
        }
    }

    func findModelFile() throws -> Data? {
        let modelPaths = [
            "3D/3dmodel.model",
            "3d/3dmodel.model",
            "3D/Model.model",
            "3d/model.model"
        ]

        for path in modelPaths {
            if let entry = entries.first(where: { $0.filename.lowercased() == path.lowercased() }) {
                return try extractEntry(entry)
            }
        }

        if let entry = entries.first(where: { $0.filename.lowercased().hasSuffix(".model") }) {
            return try extractEntry(entry)
        }

        return nil
    }

    /// Extract a file by path from the archive
    func extractFile(path: String) throws -> Data? {
        // Try exact match first
        if let entry = entries.first(where: { $0.filename == path }) {
            return try extractEntry(entry)
        }
        // Try case-insensitive match
        if let entry = entries.first(where: { $0.filename.lowercased() == path.lowercased() }) {
            return try extractEntry(entry)
        }
        return nil
    }

    private func extractEntry(_ entry: ZipEntry) throws -> Data? {
        let localOffset = Int(entry.localHeaderOffset)

        guard localOffset + 30 < data.count,
              data[localOffset] == 0x50 && data[localOffset + 1] == 0x4B &&
              data[localOffset + 2] == 0x03 && data[localOffset + 3] == 0x04 else {
            return nil
        }

        let filenameLength = readUInt16(at: localOffset + 26)
        let extraLength = readUInt16(at: localOffset + 28)

        let dataStart = localOffset + 30 + Int(filenameLength) + Int(extraLength)
        let dataEnd = dataStart + Int(entry.compressedSize)

        guard dataEnd <= data.count else { return nil }

        let compressedData = data[dataStart..<dataEnd]

        if entry.compressionMethod == 0 {
            return Data(compressedData)
        } else if entry.compressionMethod == 8 {
            return decompressDeflate(Data(compressedData), uncompressedSize: Int(entry.uncompressedSize))
        }

        return nil
    }

    private func readUInt16(at offset: Int) -> UInt16 {
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        return UInt32(data[offset]) |
               (UInt32(data[offset + 1]) << 8) |
               (UInt32(data[offset + 2]) << 16) |
               (UInt32(data[offset + 3]) << 24)
    }

    private func decompressDeflate(_ compressedData: Data, uncompressedSize: Int) -> Data? {
        let bufferSize = max(uncompressedSize, compressedData.count * 4)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }

        let decodedSize = compressedData.withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePtr = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }

            return compression_decode_buffer(
                destinationBuffer,
                bufferSize,
                sourcePtr,
                compressedData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decodedSize > 0 else { return nil }

        return Data(bytes: destinationBuffer, count: decodedSize)
    }
}

// MARK: - Errors

enum ThreeMFError: LocalizedError {
    case invalidZipFormat
    case modelFileNotFound
    case xmlParsingFailed
    case invalidMeshData(String)

    var errorDescription: String? {
        switch self {
        case .invalidZipFormat:
            return "Invalid 3MF file: not a valid ZIP archive"
        case .modelFileNotFound:
            return "3MF file does not contain a model file"
        case .xmlParsingFailed:
            return "Failed to parse 3MF model XML"
        case .invalidMeshData(let message):
            return "Invalid mesh data: \(message)"
        }
    }
}
