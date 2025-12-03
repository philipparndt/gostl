import Foundation
import Compression

/// Parser for 3MF files (3D Manufacturing Format)
/// 3MF files are ZIP archives containing XML model data
enum ThreeMFParser {

    // MARK: - Public API

    /// Parse a 3MF file from a URL
    static func parse(url: URL) throws -> STLModel {
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        return try parse(data: data, name: name)
    }

    /// Parse 3MF data
    static func parse(data: Data, name: String? = nil) throws -> STLModel {
        // 3MF is a ZIP archive - extract and parse
        let archive = try ZipArchive(data: data)

        // Find the 3D model file (usually 3D/3dmodel.model)
        guard let modelData = try archive.findModelFile() else {
            throw ThreeMFError.modelFileNotFound
        }

        // Parse the XML model
        let triangles = try parseModelXML(data: modelData)

        return STLModel(triangles: triangles, name: name)
    }

    // MARK: - XML Parsing

    private static func parseModelXML(data: Data) throws -> [Triangle] {
        let parser = ThreeMFXMLParser(data: data)
        return try parser.parse()
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
    var components: [(objectId: Int, transform: Transform3D)] = []
}

// MARK: - Build Item

private struct BuildItem {
    let objectId: Int
    let transform: Transform3D
}

// MARK: - XML Parser

private class ThreeMFXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var parseError: Error?

    // Objects by ID
    private var objects: [Int: ThreeMFObject] = [:]
    private var buildItems: [BuildItem] = []

    // Current parsing state
    private var currentObjectId: Int?
    private var vertices: [Vector3] = []
    private var inMesh = false
    private var inVertices = false
    private var inTriangles = false
    private var inComponents = false
    private var inBuild = false

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> [Triangle] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true

        guard parser.parse() else {
            if let error = parseError {
                throw error
            }
            throw ThreeMFError.xmlParsingFailed
        }

        // Build final triangles by processing build items
        return buildFinalMesh()
    }

    /// Recursively collect triangles from an object, applying transforms
    private func collectTriangles(objectId: Int, transform: Transform3D, inheritedPid: Int? = nil) -> [Triangle] {
        guard let obj = objects[objectId] else { return [] }

        var result: [Triangle] = []

        // Use object's pid if available, otherwise use inherited pid
        let effectivePid = obj.pid ?? inheritedPid
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

        // Recursively process components, passing down the pid
        for component in obj.components {
            let combinedTransform = transform.multiply(component.transform)
            result.append(contentsOf: collectTriangles(objectId: component.objectId, transform: combinedTransform, inheritedPid: effectivePid))
        }

        return result
    }

    /// Build the final mesh from build items
    private func buildFinalMesh() -> [Triangle] {
        var allTriangles: [Triangle] = []

        if buildItems.isEmpty {
            // No build section - just collect all object triangles directly
            for (_, obj) in objects {
                if !obj.triangles.isEmpty {
                    allTriangles.append(contentsOf: obj.triangles)
                }
            }
        } else {
            // Process build items with transforms
            for item in buildItems {
                allTriangles.append(contentsOf: collectTriangles(objectId: item.objectId, transform: item.transform))
            }
        }

        return allTriangles
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

        objects[parentObjectId]?.components.append((objectId: objectId, transform: transform))
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
