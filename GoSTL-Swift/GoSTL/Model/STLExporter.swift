import Foundation

/// Errors that can occur during STL export
enum STLExportError: LocalizedError {
    case emptyModel
    case writeFailure(String)

    var errorDescription: String? {
        switch self {
        case .emptyModel:
            return "Cannot export empty model"
        case .writeFailure(let message):
            return "Failed to write STL file: \(message)"
        }
    }
}

/// Exports STLModel to STL file format
enum STLExporter {
    /// Export model to binary STL format
    /// - Parameters:
    ///   - model: The model to export
    ///   - url: The destination URL
    static func exportBinary(model: STLModel, to url: URL) throws {
        guard !model.triangles.isEmpty else {
            throw STLExportError.emptyModel
        }

        var data = Data()

        // Header: 80 bytes (can contain description or be empty)
        let header = "GoSTL Export - \(model.name ?? "Untitled")"
        var headerBytes = [UInt8](repeating: 0, count: 80)
        let headerData = header.utf8.prefix(80)
        for (index, byte) in headerData.enumerated() {
            headerBytes[index] = byte
        }
        data.append(contentsOf: headerBytes)

        // Triangle count: 4 bytes (UInt32, little-endian)
        var triangleCount = UInt32(model.triangles.count)
        data.append(contentsOf: withUnsafeBytes(of: &triangleCount) { Array($0) })

        // Each triangle: 50 bytes
        for triangle in model.triangles {
            // Normal: 3 x Float32 = 12 bytes
            appendFloat32(&data, Float(triangle.normal.x))
            appendFloat32(&data, Float(triangle.normal.y))
            appendFloat32(&data, Float(triangle.normal.z))

            // Vertex 1: 3 x Float32 = 12 bytes
            appendFloat32(&data, Float(triangle.v1.x))
            appendFloat32(&data, Float(triangle.v1.y))
            appendFloat32(&data, Float(triangle.v1.z))

            // Vertex 2: 3 x Float32 = 12 bytes
            appendFloat32(&data, Float(triangle.v2.x))
            appendFloat32(&data, Float(triangle.v2.y))
            appendFloat32(&data, Float(triangle.v2.z))

            // Vertex 3: 3 x Float32 = 12 bytes
            appendFloat32(&data, Float(triangle.v3.x))
            appendFloat32(&data, Float(triangle.v3.y))
            appendFloat32(&data, Float(triangle.v3.z))

            // Attribute byte count: 2 bytes (UInt16, usually 0)
            var attributeByteCount: UInt16 = 0
            data.append(contentsOf: withUnsafeBytes(of: &attributeByteCount) { Array($0) })
        }

        // Write to file
        do {
            try data.write(to: url)
        } catch {
            throw STLExportError.writeFailure(error.localizedDescription)
        }
    }

    /// Export model to ASCII STL format
    /// - Parameters:
    ///   - model: The model to export
    ///   - url: The destination URL
    static func exportASCII(model: STLModel, to url: URL) throws {
        guard !model.triangles.isEmpty else {
            throw STLExportError.emptyModel
        }

        var output = "solid \(model.name ?? "model")\n"

        for triangle in model.triangles {
            output += "  facet normal \(formatFloat(triangle.normal.x)) \(formatFloat(triangle.normal.y)) \(formatFloat(triangle.normal.z))\n"
            output += "    outer loop\n"
            output += "      vertex \(formatFloat(triangle.v1.x)) \(formatFloat(triangle.v1.y)) \(formatFloat(triangle.v1.z))\n"
            output += "      vertex \(formatFloat(triangle.v2.x)) \(formatFloat(triangle.v2.y)) \(formatFloat(triangle.v2.z))\n"
            output += "      vertex \(formatFloat(triangle.v3.x)) \(formatFloat(triangle.v3.y)) \(formatFloat(triangle.v3.z))\n"
            output += "    endloop\n"
            output += "  endfacet\n"
        }

        output += "endsolid \(model.name ?? "model")\n"

        // Write to file
        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw STLExportError.writeFailure(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    /// Append a Float32 in little-endian format to the data
    private static func appendFloat32(_ data: inout Data, _ value: Float) {
        var floatValue = value
        data.append(contentsOf: withUnsafeBytes(of: &floatValue) { Array($0) })
    }

    /// Format a double as a string for ASCII STL
    private static func formatFloat(_ value: Double) -> String {
        return String(format: "%.6e", value)
    }
}
