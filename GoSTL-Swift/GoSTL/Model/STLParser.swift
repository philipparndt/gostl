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

        // Parse chunks in parallel, also computing partial bounds
        let actualChunkCount = splitPoints.count - 1

        // Store results with bounds
        final class ChunkResult: @unchecked Sendable {
            var triangles: [Triangle] = []
            var bounds: BoundingBox = BoundingBox()
        }
        let chunkResults = (0..<actualChunkCount).map { _ in ChunkResult() }

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
                let result = chunkResults[chunkIndex]
                result.triangles = parseASCIIChunk(bytes: bytesWrapper.ptr, start: start, end: end)

                // Compute bounds for this chunk
                var minX = Double.infinity, minY = Double.infinity, minZ = Double.infinity
                var maxX = -Double.infinity, maxY = -Double.infinity, maxZ = -Double.infinity
                for triangle in result.triangles {
                    minX = min(minX, triangle.v1.x, triangle.v2.x, triangle.v3.x)
                    minY = min(minY, triangle.v1.y, triangle.v2.y, triangle.v3.y)
                    minZ = min(minZ, triangle.v1.z, triangle.v2.z, triangle.v3.z)
                    maxX = max(maxX, triangle.v1.x, triangle.v2.x, triangle.v3.x)
                    maxY = max(maxY, triangle.v1.y, triangle.v2.y, triangle.v3.y)
                    maxZ = max(maxZ, triangle.v1.z, triangle.v2.z, triangle.v3.z)
                }
                if !result.triangles.isEmpty {
                    result.bounds = BoundingBox(min: Vector3(minX, minY, minZ), max: Vector3(maxX, maxY, maxZ))
                }
            }
        }

        // Merge results and bounds
        var allTriangles: [Triangle] = []
        allTriangles.reserveCapacity(data.count / 250)
        var finalBounds: BoundingBox?

        for result in chunkResults {
            allTriangles.append(contentsOf: result.triangles)
            if !result.triangles.isEmpty {
                if var bounds = finalBounds {
                    bounds.extend(result.bounds)
                    finalBounds = bounds
                } else {
                    finalBounds = result.bounds
                }
            }
        }

        return STLModel(triangles: allTriangles, name: name, precomputedBounds: finalBounds)
    }

    /// Parse a chunk of ASCII STL data - optimized direct vertex scanning
    private static func parseASCIIChunk(bytes: UnsafePointer<UInt8>, start: Int, end: Int) -> [Triangle] {
        var triangles: [Triangle] = []
        triangles.reserveCapacity((end - start) / 250)

        // Vertex buffer for building triangles
        var v1: Vector3?
        var v2: Vector3?

        var i = start

        // Scan for "vertex" keyword directly (much faster than line-by-line)
        // v=0x76/0x56, e=0x65/0x45, r=0x72/0x52, t=0x74/0x54, e=0x65/0x45, x=0x78/0x58
        while i < end - 10 {  // Need at least "vertex X Y Z"
            let b0 = bytes[i]

            // Quick check: is this 'v' or 'V'?
            if b0 == 0x76 || b0 == 0x56 {
                // Check for "vertex" (case insensitive)
                if (bytes[i + 1] == 0x65 || bytes[i + 1] == 0x45) &&  // e
                   (bytes[i + 2] == 0x72 || bytes[i + 2] == 0x52) &&  // r
                   (bytes[i + 3] == 0x74 || bytes[i + 3] == 0x54) &&  // t
                   (bytes[i + 4] == 0x65 || bytes[i + 4] == 0x45) &&  // e
                   (bytes[i + 5] == 0x78 || bytes[i + 5] == 0x58) {   // x

                    // Found "vertex", parse the 3 floats
                    let charPtr = UnsafeRawPointer(bytes + i + 6).assumingMemoryBound(to: CChar.self)
                    var endPtr: UnsafeMutablePointer<CChar>?

                    let x = strtod(charPtr, &endPtr)
                    guard let e1 = endPtr, e1 > charPtr else { i += 1; continue }

                    let y = strtod(e1, &endPtr)
                    guard let e2 = endPtr, e2 > e1 else { i += 1; continue }

                    let z = strtod(e2, &endPtr)
                    guard let e3 = endPtr, e3 > e2 else { i += 1; continue }

                    let vertex = Vector3(x, y, z)

                    // Build triangles from every 3 vertices
                    if v1 == nil {
                        v1 = vertex
                    } else if v2 == nil {
                        v2 = vertex
                    } else {
                        triangles.append(Triangle(v1: v1!, v2: v2!, v3: vertex))
                        v1 = nil
                        v2 = nil
                    }

                    // Skip past parsed content
                    let basePtr = UnsafeRawPointer(bytes).assumingMemoryBound(to: CChar.self)
                    i = Int(bitPattern: e3) - Int(bitPattern: basePtr)
                    continue
                }
            }
            i += 1
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

        // Track bounds during parsing
        var minX = Double.infinity, minY = Double.infinity, minZ = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity, maxZ = -Double.infinity

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
                    let prevCount = triangles.count
                    processASCIILineIntoArray(bytes: bytes, start: lineStart, end: i,
                                    triangles: &triangles,
                                    currentVertices: &currentVertices,
                                    currentNormal: &currentNormal)
                    // Update bounds if a triangle was added
                    if triangles.count > prevCount {
                        let triangle = triangles[triangles.count - 1]
                        minX = min(minX, triangle.v1.x, triangle.v2.x, triangle.v3.x)
                        minY = min(minY, triangle.v1.y, triangle.v2.y, triangle.v3.y)
                        minZ = min(minZ, triangle.v1.z, triangle.v2.z, triangle.v3.z)
                        maxX = max(maxX, triangle.v1.x, triangle.v2.x, triangle.v3.x)
                        maxY = max(maxY, triangle.v1.y, triangle.v2.y, triangle.v3.y)
                        maxZ = max(maxZ, triangle.v1.z, triangle.v2.z, triangle.v3.z)
                    }
                }

                while i < count && (bytes[i] == 0x0A || bytes[i] == 0x0D) {
                    i += 1
                }
                lineStart = i
            }
        }

        let bounds = triangles.isEmpty ? nil
            : BoundingBox(min: Vector3(minX, minY, minZ), max: Vector3(maxX, maxY, maxZ))

        return STLModel(triangles: triangles, name: name, precomputedBounds: bounds)
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

    /// Sequential binary parsing for small files using direct memory access
    private static func parseBinarySequential(data: Data, triangleCount: Int, name: String?) -> STLModel {
        var triangles: [Triangle] = []
        triangles.reserveCapacity(triangleCount)

        // Track bounds during parsing
        var minX = Double.infinity, minY = Double.infinity, minZ = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity, maxZ = -Double.infinity

        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let baseAddress = buffer.baseAddress else { return }
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

            for i in 0..<triangleCount {
                let offset = 84 + (i * 50)
                let triangle = parseTriangleDirect(bytes: bytes, offset: offset)
                triangles.append(triangle)

                // Update bounds inline
                minX = min(minX, triangle.v1.x, triangle.v2.x, triangle.v3.x)
                minY = min(minY, triangle.v1.y, triangle.v2.y, triangle.v3.y)
                minZ = min(minZ, triangle.v1.z, triangle.v2.z, triangle.v3.z)
                maxX = max(maxX, triangle.v1.x, triangle.v2.x, triangle.v3.x)
                maxY = max(maxY, triangle.v1.y, triangle.v2.y, triangle.v3.y)
                maxZ = max(maxZ, triangle.v1.z, triangle.v2.z, triangle.v3.z)
            }
        }

        let bounds = triangleCount > 0
            ? BoundingBox(min: Vector3(minX, minY, minZ), max: Vector3(maxX, maxY, maxZ))
            : nil

        return STLModel(triangles: triangles, name: name, precomputedBounds: bounds)
    }

    /// Parallel binary parsing for large files using direct memory access
    private static func parseBinaryParallel(data: Data, triangleCount: Int, name: String?) -> STLModel {
        // Pre-allocate array with placeholder triangles
        let triangles = ParallelArray([Triangle](repeating: Triangle(v1: .zero, v2: .zero, v3: .zero), count: triangleCount))

        // Pre-allocate partial bounding boxes for parallel computation
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let chunkSize = max(1000, triangleCount / processorCount)
        let chunkCount = (triangleCount + chunkSize - 1) / chunkSize
        let partialBounds = ParallelArray([BoundingBox](repeating: BoundingBox(), count: chunkCount))

        // Use direct memory access for maximum performance
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let baseAddress = buffer.baseAddress else { return }
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

            // Wrap pointer for safe concurrent access
            final class BytesWrapper: @unchecked Sendable {
                let ptr: UnsafePointer<UInt8>
                init(_ ptr: UnsafePointer<UInt8>) { self.ptr = ptr }
            }
            let bytesWrapper = BytesWrapper(bytes)

            // Parse in parallel chunks with direct memory access
            DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
                let startIndex = chunkIndex * chunkSize
                let endIndex = min(startIndex + chunkSize, triangleCount)
                let ptr = bytesWrapper.ptr

                // Track bounds for this chunk
                var minX = Double.infinity, minY = Double.infinity, minZ = Double.infinity
                var maxX = -Double.infinity, maxY = -Double.infinity, maxZ = -Double.infinity

                for i in startIndex..<endIndex {
                    let offset = 84 + (i * 50)
                    let triangle = parseTriangleDirect(bytes: ptr, offset: offset)
                    triangles[i] = triangle

                    // Update bounds inline (essentially free)
                    minX = min(minX, triangle.v1.x, triangle.v2.x, triangle.v3.x)
                    minY = min(minY, triangle.v1.y, triangle.v2.y, triangle.v3.y)
                    minZ = min(minZ, triangle.v1.z, triangle.v2.z, triangle.v3.z)
                    maxX = max(maxX, triangle.v1.x, triangle.v2.x, triangle.v3.x)
                    maxY = max(maxY, triangle.v1.y, triangle.v2.y, triangle.v3.y)
                    maxZ = max(maxZ, triangle.v1.z, triangle.v2.z, triangle.v3.z)
                }

                partialBounds[chunkIndex] = BoundingBox(
                    min: Vector3(minX, minY, minZ),
                    max: Vector3(maxX, maxY, maxZ)
                )
            }
        }

        // Merge partial bounds
        var finalBounds = partialBounds.storage[0]
        for i in 1..<chunkCount {
            finalBounds.extend(partialBounds.storage[i])
        }

        return STLModel(triangles: triangles.storage, name: name, precomputedBounds: finalBounds)
    }

    /// Parse a single triangle using direct memory access (no copying)
    @inline(__always)
    private static func parseTriangleDirect(bytes: UnsafePointer<UInt8>, offset: Int) -> Triangle {
        // Read all 12 floats directly from memory (normal + 3 vertices)
        let floatPtr = UnsafeRawPointer(bytes + offset).assumingMemoryBound(to: Float.self)

        let nx = Double(floatPtr[0])
        let ny = Double(floatPtr[1])
        let nz = Double(floatPtr[2])

        let v1x = Double(floatPtr[3])
        let v1y = Double(floatPtr[4])
        let v1z = Double(floatPtr[5])

        let v2x = Double(floatPtr[6])
        let v2y = Double(floatPtr[7])
        let v2z = Double(floatPtr[8])

        let v3x = Double(floatPtr[9])
        let v3y = Double(floatPtr[10])
        let v3z = Double(floatPtr[11])

        return Triangle(
            v1: Vector3(v1x, v1y, v1z),
            v2: Vector3(v2x, v2y, v2z),
            v3: Vector3(v3x, v3y, v3z),
            normal: Vector3(nx, ny, nz)
        )
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
