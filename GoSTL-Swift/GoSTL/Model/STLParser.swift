import Foundation

/// Parser for STL files (both ASCII and Binary formats)
enum STLParser {

    // MARK: - Public API

    /// Parse an STL file from a URL
    static func parse(url: URL) throws -> STLModel {
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        return try parse(data: data, name: name)
    }

    /// Parse STL data
    static func parse(data: Data, name: String? = nil) throws -> STLModel {
        let format = detectFormat(data: data)

        switch format {
        case .ascii:
            return try parseASCII(data: data, name: name)
        case .binary:
            return try parseBinary(data: data, name: name)
        }
    }

    // MARK: - Format Detection

    enum Format {
        case ascii
        case binary
    }

    private static func detectFormat(data: Data) -> Format {
        // Check first 5 bytes for "solid" keyword (ASCII)
        guard data.count >= 5 else { return .binary }

        let prefix = data.prefix(5)
        if let string = String(data: prefix, encoding: .ascii),
           string.lowercased() == "solid" {
            // Further validation: ASCII files should be mostly printable
            // Check if first 100 bytes are ASCII
            let sampleSize = min(100, data.count)
            let sample = data.prefix(sampleSize)

            let asciiCount = sample.filter { $0 >= 32 && $0 <= 126 || $0 == 10 || $0 == 13 }.count
            let asciiRatio = Double(asciiCount) / Double(sampleSize)

            if asciiRatio > 0.9 {
                return .ascii
            }
        }

        return .binary
    }

    // MARK: - ASCII Parser

    private static func parseASCII(data: Data, name: String?) throws -> STLModel {
        guard let content = String(data: data, encoding: .ascii) else {
            throw STLError.invalidFormat("Could not decode ASCII data")
        }

        var triangles: [Triangle] = []
        var currentVertices: [Vector3] = []
        var currentNormal: Vector3?

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            guard !parts.isEmpty else { continue }

            switch parts[0].lowercased() {
            case "facet":
                // facet normal nx ny nz
                guard parts.count >= 5, parts[1].lowercased() == "normal" else { continue }
                guard let nx = Double(parts[2]),
                      let ny = Double(parts[3]),
                      let nz = Double(parts[4]) else {
                    throw STLError.invalidFormat("Invalid normal values")
                }
                currentNormal = Vector3(nx, ny, nz)

            case "vertex":
                // vertex x y z
                guard parts.count >= 4 else {
                    throw STLError.invalidFormat("Invalid vertex format")
                }
                guard let x = Double(parts[1]),
                      let y = Double(parts[2]),
                      let z = Double(parts[3]) else {
                    throw STLError.invalidFormat("Invalid vertex values")
                }
                currentVertices.append(Vector3(x, y, z))

            case "endfacet":
                // Create triangle from collected vertices
                guard currentVertices.count == 3 else {
                    throw STLError.invalidFormat("Triangle must have exactly 3 vertices")
                }

                let triangle = Triangle(
                    v1: currentVertices[0],
                    v2: currentVertices[1],
                    v3: currentVertices[2],
                    normal: currentNormal
                )
                triangles.append(triangle)

                currentVertices.removeAll(keepingCapacity: true)
                currentNormal = nil

            default:
                break
            }
        }

        return STLModel(triangles: triangles, name: name)
    }

    // MARK: - Binary Parser

    private static func parseBinary(data: Data, name: String?) throws -> STLModel {
        guard data.count >= 84 else {
            throw STLError.fileTooSmall
        }

        // Binary STL structure:
        // 80 bytes: Header
        // 4 bytes: Triangle count (uint32)
        // For each triangle (50 bytes):
        //   12 bytes: Normal (3 x float32)
        //   12 bytes: Vertex 1 (3 x float32)
        //   12 bytes: Vertex 2 (3 x float32)
        //   12 bytes: Vertex 3 (3 x float32)
        //   2 bytes: Attribute byte count (uint16, usually 0)

        var offset = 80 // Skip header

        // Read triangle count
        let triangleCount = data.readUInt32(at: offset)
        offset += 4

        let expectedSize = 84 + (Int(triangleCount) * 50)
        guard data.count >= expectedSize else {
            throw STLError.inconsistentSize
        }

        var triangles: [Triangle] = []
        triangles.reserveCapacity(Int(triangleCount))

        for _ in 0..<triangleCount {
            // Read normal (3 floats)
            let nx = data.readFloat32(at: offset)
            let ny = data.readFloat32(at: offset + 4)
            let nz = data.readFloat32(at: offset + 8)
            offset += 12

            // Read vertex 1
            let v1x = data.readFloat32(at: offset)
            let v1y = data.readFloat32(at: offset + 4)
            let v1z = data.readFloat32(at: offset + 8)
            offset += 12

            // Read vertex 2
            let v2x = data.readFloat32(at: offset)
            let v2y = data.readFloat32(at: offset + 4)
            let v2z = data.readFloat32(at: offset + 8)
            offset += 12

            // Read vertex 3
            let v3x = data.readFloat32(at: offset)
            let v3y = data.readFloat32(at: offset + 4)
            let v3z = data.readFloat32(at: offset + 8)
            offset += 12

            // Skip attribute byte count
            offset += 2

            let triangle = Triangle(
                v1: Vector3(Double(v1x), Double(v1y), Double(v1z)),
                v2: Vector3(Double(v2x), Double(v2y), Double(v2z)),
                v3: Vector3(Double(v3x), Double(v3y), Double(v3z)),
                normal: Vector3(Double(nx), Double(ny), Double(nz))
            )

            triangles.append(triangle)
        }

        return STLModel(triangles: triangles, name: name)
    }
}

// MARK: - Data Extensions

private extension Data {
    func readFloat32(at offset: Int) -> Float {
        // Copy bytes to ensure proper alignment
        var value: Float = 0
        withUnsafeMutablePointer(to: &value) { pointer in
            let buffer = UnsafeMutableRawBufferPointer(start: pointer, count: MemoryLayout<Float>.size)
            let range = offset..<(offset + MemoryLayout<Float>.size)
            _ = copyBytes(to: buffer, from: range)
        }
        return value
    }

    func readUInt32(at offset: Int) -> UInt32 {
        // Copy bytes to ensure proper alignment
        var value: UInt32 = 0
        withUnsafeMutablePointer(to: &value) { pointer in
            let buffer = UnsafeMutableRawBufferPointer(start: pointer, count: MemoryLayout<UInt32>.size)
            let range = offset..<(offset + MemoryLayout<UInt32>.size)
            _ = copyBytes(to: buffer, from: range)
        }
        return value
    }
}

// MARK: - Errors

enum STLError: LocalizedError {
    case fileTooSmall
    case inconsistentSize
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .fileTooSmall:
            return "File is too small to be a valid STL (minimum 84 bytes)"
        case .inconsistentSize:
            return "File size does not match expected triangle count"
        case .invalidFormat(let message):
            return "Invalid STL format: \(message)"
        }
    }
}
