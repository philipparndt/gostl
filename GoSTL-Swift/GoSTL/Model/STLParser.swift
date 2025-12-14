import Foundation

/// Thread-safe array wrapper for parallel writes to different indices
private final class ParallelArray<T>: @unchecked Sendable {
    var storage: [T]
    init(_ array: [T]) { self.storage = array }
    subscript(index: Int) -> T {
        get { storage[index] }
        set { storage[index] = newValue }
    }
}

/// Parser for STL files (both ASCII and Binary formats)
enum STLParser {

    // MARK: - Public API

    /// Parse an STL file from a URL
    static func parse(url: URL) throws -> STLModel {
        let t0 = CFAbsoluteTimeGetCurrent()
        let data = try Data(contentsOf: url)
        print("    File read: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms (\(data.count / 1_000_000)MB)")

        let name = url.deletingPathExtension().lastPathComponent
        let t1 = CFAbsoluteTimeGetCurrent()
        let model = try parse(data: data, name: name)
        print("    Parse data: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - t1) * 1000))ms")

        return model
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
        // Use parallel parsing for large files
        if data.count > 1_000_000 {
            return parseASCIIParallel(data: data, name: name)
        }
        return parseASCIISequential(data: data, name: name)
    }

    /// Parallel ASCII parsing for large files
    private static func parseASCIIParallel(data: Data, name: String?) -> STLModel {
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let chunkCount = processorCount

        // Find "endfacet" boundaries to split on
        var splitPoints: [Int] = [0]

        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let baseAddress = buffer.baseAddress else { return }
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
            let count = buffer.count
            let targetChunkSize = count / chunkCount

            for chunk in 1..<chunkCount {
                var searchStart = chunk * targetChunkSize
                // Find next "endfacet" after this point (must match full keyword)
                while searchStart < count - 8 {
                    // Check for "endfacet" (case insensitive)
                    // e/E=0x65/0x45, n/N=0x6E/0x4E, d/D=0x64/0x44, f/F=0x66/0x46, a/A=0x61/0x41, c/C=0x63/0x43, e/E, t/T=0x74/0x54
                    if (bytes[searchStart] == 0x65 || bytes[searchStart] == 0x45) &&      // e
                       (bytes[searchStart + 1] == 0x6E || bytes[searchStart + 1] == 0x4E) && // n
                       (bytes[searchStart + 2] == 0x64 || bytes[searchStart + 2] == 0x44) && // d
                       (bytes[searchStart + 3] == 0x66 || bytes[searchStart + 3] == 0x46) && // f
                       (bytes[searchStart + 4] == 0x61 || bytes[searchStart + 4] == 0x41) && // a
                       (bytes[searchStart + 5] == 0x63 || bytes[searchStart + 5] == 0x43) && // c
                       (bytes[searchStart + 6] == 0x65 || bytes[searchStart + 6] == 0x45) && // e
                       (bytes[searchStart + 7] == 0x74 || bytes[searchStart + 7] == 0x54) {  // t
                        // Find end of this line
                        var lineEnd = searchStart
                        while lineEnd < count && bytes[lineEnd] != 0x0A && bytes[lineEnd] != 0x0D {
                            lineEnd += 1
                        }
                        // Skip newlines
                        while lineEnd < count && (bytes[lineEnd] == 0x0A || bytes[lineEnd] == 0x0D) {
                            lineEnd += 1
                        }
                        if lineEnd > splitPoints.last! {
                            splitPoints.append(lineEnd)
                        }
                        break
                    }
                    searchStart += 1
                }
            }
        }
        splitPoints.append(data.count)

        // Parse chunks in parallel
        let actualChunkCount = splitPoints.count - 1
        let chunkResults = ParallelArray([[Triangle]](repeating: [], count: actualChunkCount))

        // Copy splitPoints to immutable array for safe concurrent access
        let splits = splitPoints

        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let baseAddress = buffer.baseAddress else { return }
            // Wrap pointer in Sendable wrapper for concurrent access
            final class BytesWrapper: @unchecked Sendable {
                let ptr: UnsafePointer<UInt8>
                init(_ ptr: UnsafePointer<UInt8>) { self.ptr = ptr }
            }
            let bytesWrapper = BytesWrapper(baseAddress.assumingMemoryBound(to: UInt8.self))

            DispatchQueue.concurrentPerform(iterations: actualChunkCount) { chunkIndex in
                let start = splits[chunkIndex]
                let end = splits[chunkIndex + 1]
                chunkResults[chunkIndex] = parseASCIIChunk(bytes: bytesWrapper.ptr, start: start, end: end)
            }
        }

        // Merge results
        var allTriangles: [Triangle] = []
        allTriangles.reserveCapacity(data.count / 250)
        for chunk in chunkResults.storage {
            allTriangles.append(contentsOf: chunk)
        }

        return STLModel(triangles: allTriangles, name: name)
    }

    /// Parse a chunk of ASCII STL data
    private static func parseASCIIChunk(bytes: UnsafePointer<UInt8>, start: Int, end: Int) -> [Triangle] {
        var triangles: [Triangle] = []
        triangles.reserveCapacity((end - start) / 250)

        var currentVertices: [Vector3] = []
        currentVertices.reserveCapacity(3)
        var currentNormal: Vector3?

        var lineStart = start
        var i = start

        while i < end {
            // Find end of line
            while i < end && bytes[i] != 0x0A && bytes[i] != 0x0D {
                i += 1
            }

            // Process line if non-empty
            if i > lineStart {
                processASCIILineIntoArray(bytes: bytes, start: lineStart, end: i,
                                triangles: &triangles,
                                currentVertices: &currentVertices,
                                currentNormal: &currentNormal)
            }

            // Skip newline characters
            while i < end && (bytes[i] == 0x0A || bytes[i] == 0x0D) {
                i += 1
            }
            lineStart = i
        }

        return triangles
    }

    /// Sequential ASCII parsing for small files
    private static func parseASCIISequential(data: Data, name: String?) -> STLModel {
        var triangles: [Triangle] = []
        triangles.reserveCapacity(data.count / 250)

        var currentVertices: [Vector3] = []
        currentVertices.reserveCapacity(3)
        var currentNormal: Vector3?

        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let baseAddress = buffer.baseAddress else { return }
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
            let count = buffer.count

            var lineStart = 0
            var i = 0

            while i < count {
                while i < count && bytes[i] != 0x0A && bytes[i] != 0x0D {
                    i += 1
                }

                if i > lineStart {
                    processASCIILineIntoArray(bytes: bytes, start: lineStart, end: i,
                                    triangles: &triangles,
                                    currentVertices: &currentVertices,
                                    currentNormal: &currentNormal)
                }

                while i < count && (bytes[i] == 0x0A || bytes[i] == 0x0D) {
                    i += 1
                }
                lineStart = i
            }
        }

        return STLModel(triangles: triangles, name: name)
    }

    /// Process a single ASCII line (renamed to avoid conflict)
    private static func processASCIILineIntoArray(
        bytes: UnsafePointer<UInt8>,
        start: Int,
        end: Int,
        triangles: inout [Triangle],
        currentVertices: inout [Vector3],
        currentNormal: inout Vector3?
    ) {
        var pos = start

        // Skip leading whitespace
        while pos < end && (bytes[pos] == 0x20 || bytes[pos] == 0x09) {
            pos += 1
        }

        guard pos < end else { return }

        let firstChar = bytes[pos]

        if firstChar == 0x76 || firstChar == 0x56 { // 'v' or 'V'
            if matchKeyword(bytes: bytes, pos: pos, end: end, keyword: "vertex") {
                pos += 6
                if let (x, y, z) = parseThreeDoubles(bytes: bytes, start: pos, end: end) {
                    currentVertices.append(Vector3(x, y, z))
                }
            }
        } else if firstChar == 0x66 || firstChar == 0x46 { // 'f' or 'F'
            if matchKeyword(bytes: bytes, pos: pos, end: end, keyword: "facet") {
                pos += 5
                while pos < end && (bytes[pos] == 0x20 || bytes[pos] == 0x09) {
                    pos += 1
                }
                if matchKeyword(bytes: bytes, pos: pos, end: end, keyword: "normal") {
                    pos += 6
                    if let (nx, ny, nz) = parseThreeDoubles(bytes: bytes, start: pos, end: end) {
                        currentNormal = Vector3(nx, ny, nz)
                    }
                }
            }
        } else if firstChar == 0x65 || firstChar == 0x45 { // 'e' or 'E'
            if matchKeyword(bytes: bytes, pos: pos, end: end, keyword: "endfacet") {
                if currentVertices.count == 3 {
                    triangles.append(Triangle(
                        v1: currentVertices[0],
                        v2: currentVertices[1],
                        v3: currentVertices[2],
                        normal: currentNormal
                    ))
                }
                currentVertices.removeAll(keepingCapacity: true)
                currentNormal = nil
            }
        }
    }

    /// Check if bytes at position match a keyword (case-insensitive)
    /// Using inline byte comparison to avoid Array allocation
    @inline(__always)
    private static func matchKeyword(bytes: UnsafePointer<UInt8>, pos: Int, end: Int, keyword: StaticString) -> Bool {
        let len = keyword.utf8CodeUnitCount
        guard pos + len <= end else { return false }

        return keyword.withUTF8Buffer { keywordBuffer in
            for i in 0..<len {
                let b = bytes[pos + i]
                let lower = (b >= 0x41 && b <= 0x5A) ? b + 32 : b
                if lower != keywordBuffer[i] {
                    return false
                }
            }
            return true
        }
    }

    /// Parse three doubles from bytes using strtod (highly optimized C function)
    @inline(__always)
    private static func parseThreeDoubles(bytes: UnsafePointer<UInt8>, start: Int, end: Int) -> (Double, Double, Double)? {
        // Cast to char pointer for strtod
        let charPtr = UnsafeRawPointer(bytes + start).assumingMemoryBound(to: CChar.self)
        var endPtr: UnsafeMutablePointer<CChar>?

        let v1 = strtod(charPtr, &endPtr)
        guard let e1 = endPtr, e1 > charPtr else { return nil }

        let v2 = strtod(e1, &endPtr)
        guard let e2 = endPtr, e2 > e1 else { return nil }

        let v3 = strtod(e2, &endPtr)
        guard let e3 = endPtr, e3 > e2 else { return nil }

        return (v1, v2, v3)
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

        // Read triangle count
        let triangleCount = Int(data.readUInt32(at: 80))

        let expectedSize = 84 + (triangleCount * 50)
        guard data.count >= expectedSize else {
            throw STLError.inconsistentSize
        }

        // For small files, use sequential parsing
        if triangleCount < 10000 {
            return parseBinarySequential(data: data, triangleCount: triangleCount, name: name)
        }

        // For large files, use parallel parsing
        return parseBinaryParallel(data: data, triangleCount: triangleCount, name: name)
    }

    /// Sequential binary parsing for small files
    private static func parseBinarySequential(data: Data, triangleCount: Int, name: String?) -> STLModel {
        var triangles: [Triangle] = []
        triangles.reserveCapacity(triangleCount)

        var offset = 84 // Header (80) + count (4)

        for _ in 0..<triangleCount {
            let triangle = parseTriangleAt(data: data, offset: offset)
            triangles.append(triangle)
            offset += 50
        }

        return STLModel(triangles: triangles, name: name)
    }

    /// Parallel binary parsing for large files
    private static func parseBinaryParallel(data: Data, triangleCount: Int, name: String?) -> STLModel {
        // Pre-allocate array with placeholder triangles
        let triangles = ParallelArray([Triangle](repeating: Triangle(v1: .zero, v2: .zero, v3: .zero), count: triangleCount))

        // Determine chunk size based on CPU cores
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let chunkSize = max(1000, triangleCount / processorCount)

        // Parse in parallel chunks
        DispatchQueue.concurrentPerform(iterations: (triangleCount + chunkSize - 1) / chunkSize) { chunkIndex in
            let startIndex = chunkIndex * chunkSize
            let endIndex = min(startIndex + chunkSize, triangleCount)

            for i in startIndex..<endIndex {
                let offset = 84 + (i * 50)
                triangles[i] = parseTriangleAt(data: data, offset: offset)
            }
        }

        return STLModel(triangles: triangles.storage, name: name)
    }

    /// Parse a single triangle at a given byte offset
    @inline(__always)
    private static func parseTriangleAt(data: Data, offset: Int) -> Triangle {
        // Read normal (3 floats)
        let nx = data.readFloat32(at: offset)
        let ny = data.readFloat32(at: offset + 4)
        let nz = data.readFloat32(at: offset + 8)

        // Read vertex 1
        let v1x = data.readFloat32(at: offset + 12)
        let v1y = data.readFloat32(at: offset + 16)
        let v1z = data.readFloat32(at: offset + 20)

        // Read vertex 2
        let v2x = data.readFloat32(at: offset + 24)
        let v2y = data.readFloat32(at: offset + 28)
        let v2z = data.readFloat32(at: offset + 32)

        // Read vertex 3
        let v3x = data.readFloat32(at: offset + 36)
        let v3y = data.readFloat32(at: offset + 40)
        let v3z = data.readFloat32(at: offset + 44)

        return Triangle(
            v1: Vector3(Double(v1x), Double(v1y), Double(v1z)),
            v2: Vector3(Double(v2x), Double(v2y), Double(v2z)),
            v3: Vector3(Double(v3x), Double(v3y), Double(v3z)),
            normal: Vector3(Double(nx), Double(ny), Double(nz))
        )
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
