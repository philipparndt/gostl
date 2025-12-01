import Metal
import simd

/// GPU-ready wireframe data for edge rendering using instanced cylinders
final class WireframeData {
    let cylinderVertexBuffer: MTLBuffer
    let cylinderIndexBuffer: MTLBuffer
    let instanceBuffer: MTLBuffer
    let indexCount: Int
    let instanceCount: Int

    /// Initialize wireframe from a model (extracts edges internally)
    convenience init(device: MTLDevice, model: STLModel, thickness: Float = 0.005, sliceBounds: [[Double]]? = nil) throws {
        try self.init(device: device, edges: model.extractEdges(), thickness: thickness, sliceBounds: sliceBounds)
    }

    /// Initialize wireframe from pre-extracted edges (faster for repeated slicing)
    init(device: MTLDevice, edges: [Edge], thickness: Float = 0.005, sliceBounds: [[Double]]? = nil) throws {
        // Clip edges to bounds (parallelized for large edge counts)
        let clippedEdges: [Edge]
        if let bounds = sliceBounds {
            clippedEdges = Self.clipEdgesParallel(edges, bounds: bounds)
        } else {
            clippedEdges = edges
        }

        self.instanceCount = clippedEdges.count

        // Create unit cylinder geometry (along Y-axis, from 0 to 1)
        let cylinderGeometry = WireframeData.createCylinderGeometry(radius: thickness, segments: 8)
        self.indexCount = cylinderGeometry.indices.count

        // Create vertex buffer for cylinder
        let vertexSize = cylinderGeometry.vertices.count * MemoryLayout<VertexIn>.stride
        guard let vertexBuffer = device.makeBuffer(bytes: cylinderGeometry.vertices, length: vertexSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.cylinderVertexBuffer = vertexBuffer

        // Create index buffer for cylinder
        let indexSize = cylinderGeometry.indices.count * MemoryLayout<UInt16>.stride
        guard let indexBuffer = device.makeBuffer(bytes: cylinderGeometry.indices, length: indexSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.cylinderIndexBuffer = indexBuffer

        // Create instance buffer with transformation matrices for each edge (parallelized)
        let instances = Self.createInstanceMatricesParallel(edges: clippedEdges)

        let instanceSize = instances.count * MemoryLayout<simd_float4x4>.stride
        guard let instanceBuffer = device.makeBuffer(bytes: instances, length: instanceSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.instanceBuffer = instanceBuffer
    }

    // MARK: - Parallel Processing

    /// Container for parallel edge clipping results
    private final class EdgeChunkResult: @unchecked Sendable {
        var edges: [Edge] = []
    }

    /// Clip edges in parallel for better performance on large edge counts
    private static func clipEdgesParallel(_ edges: [Edge], bounds: [[Double]]) -> [Edge] {
        let chunkSize = max(1000, edges.count / ProcessInfo.processInfo.activeProcessorCount)
        let chunkCount = (edges.count + chunkSize - 1) / chunkSize

        // Pre-allocate result containers
        let chunkResults = (0..<chunkCount).map { _ in EdgeChunkResult() }

        // Process chunks in parallel
        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            let startIdx = chunkIndex * chunkSize
            let endIdx = min(startIdx + chunkSize, edges.count)
            let result = chunkResults[chunkIndex]

            result.edges.reserveCapacity(endIdx - startIdx)

            for i in startIdx..<endIdx {
                if let clipped = clipEdgeToBounds(edges[i], bounds: bounds) {
                    result.edges.append(clipped)
                }
            }
        }

        // Merge results
        var finalResult: [Edge] = []
        finalResult.reserveCapacity(edges.count)
        for result in chunkResults {
            finalResult.append(contentsOf: result.edges)
        }

        return finalResult
    }

    /// Container for parallel matrix results
    private final class MatrixBuffer: @unchecked Sendable {
        var matrices: [simd_float4x4]

        init(count: Int) {
            matrices = [simd_float4x4](repeating: matrix_identity_float4x4, count: count)
        }
    }

    /// Create instance matrices in parallel
    private static func createInstanceMatricesParallel(edges: [Edge]) -> [simd_float4x4] {
        guard !edges.isEmpty else { return [] }

        // For small counts, use serial
        if edges.count < 1000 {
            return createInstanceMatrices(edges: edges)
        }

        // Pre-allocate the result array in a Sendable container
        let buffer = MatrixBuffer(count: edges.count)

        // Process in parallel - each index is only written by one thread
        let chunkSize = max(500, edges.count / ProcessInfo.processInfo.activeProcessorCount)
        let chunkCount = (edges.count + chunkSize - 1) / chunkSize

        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            let startIdx = chunkIndex * chunkSize
            let endIdx = min(startIdx + chunkSize, edges.count)

            for i in startIdx..<endIdx {
                buffer.matrices[i] = createEdgeMatrix(start: edges[i].start.float3, end: edges[i].end.float3)
            }
        }

        return buffer.matrices
    }

    // MARK: - Cylinder Geometry

    private static func createCylinderGeometry(radius: Float, segments: Int) -> (vertices: [VertexIn], indices: [UInt16]) {
        var vertices: [VertexIn] = []
        var indices: [UInt16] = []

        let color = SIMD4<Float>(0.2, 0.2, 0.2, 1.0) // Dark gray for wireframe

        // Create vertices for bottom and top circles
        for i in 0...segments {
            let theta = Float(i) * 2.0 * .pi / Float(segments)
            let x = radius * cos(theta)
            let z = radius * sin(theta)
            let normal = simd_normalize(SIMD3<Float>(x, 0, z))

            // Bottom vertex (y = 0)
            vertices.append(VertexIn(
                position: SIMD3(x, 0, z),
                normal: normal,
                color: color
            ))

            // Top vertex (y = 1)
            vertices.append(VertexIn(
                position: SIMD3(x, 1, z),
                normal: normal,
                color: color
            ))
        }

        // Create triangle indices for cylinder sides
        for i in 0..<segments {
            let base = UInt16(i * 2)

            // Two triangles per segment
            indices.append(base)
            indices.append(base + 2)
            indices.append(base + 1)

            indices.append(base + 1)
            indices.append(base + 2)
            indices.append(base + 3)
        }

        return (vertices, indices)
    }

    // MARK: - Instance Matrices

    /// Create transformation matrix for each edge (positions and orients cylinder along edge)
    private static func createInstanceMatrices(edges: [Edge]) -> [simd_float4x4] {
        edges.map { edge in
            createEdgeMatrix(start: edge.start.float3, end: edge.end.float3)
        }
    }

    /// Create a transformation matrix that positions and orients a unit cylinder (0,0,0)→(0,1,0) along an edge
    private static func createEdgeMatrix(start: SIMD3<Float>, end: SIMD3<Float>) -> simd_float4x4 {
        let direction = end - start
        let length = simd_length(direction)
        let up = direction / length

        // Create rotation matrix to align Y-axis with edge direction
        let arbitrary = abs(up.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let right = simd_normalize(simd_cross(arbitrary, up))
        let forward = simd_cross(up, right)

        // Create transformation matrix: rotation * scale * translation
        var matrix = simd_float4x4(1.0) // Identity

        // Set rotation part
        matrix[0] = SIMD4(right.x, right.y, right.z, 0)
        matrix[1] = SIMD4(up.x * length, up.y * length, up.z * length, 0) // Scale Y by edge length
        matrix[2] = SIMD4(forward.x, forward.y, forward.z, 0)

        // Set translation to start point
        matrix[3] = SIMD4(start.x, start.y, start.z, 1)

        return matrix
    }

    /// Clip an edge to slice bounds, preserving original direction
    /// Returns nil if edge is completely outside bounds
    @inline(__always)
    private static func clipEdgeToBounds(_ edge: Edge, bounds: [[Double]]) -> Edge? {
        let p1 = edge.start
        let p2 = edge.end

        // Ultra-fast bounding box rejection test (unrolled for performance)
        // X axis
        let x1 = p1.x, x2 = p2.x
        let xMin = bounds[0][0], xMax = bounds[0][1]
        let edgeXMin = x1 < x2 ? x1 : x2
        let edgeXMax = x1 > x2 ? x1 : x2
        if edgeXMax < xMin || edgeXMin > xMax { return nil }

        // Y axis
        let y1 = p1.y, y2 = p2.y
        let yMin = bounds[1][0], yMax = bounds[1][1]
        let edgeYMin = y1 < y2 ? y1 : y2
        let edgeYMax = y1 > y2 ? y1 : y2
        if edgeYMax < yMin || edgeYMin > yMax { return nil }

        // Z axis
        let z1 = p1.z, z2 = p2.z
        let zMin = bounds[2][0], zMax = bounds[2][1]
        let edgeZMin = z1 < z2 ? z1 : z2
        let edgeZMax = z1 > z2 ? z1 : z2
        if edgeZMax < zMin || edgeZMin > zMax { return nil }

        // Fast path: edge completely inside - no clipping needed
        let p1Inside = x1 >= xMin && x1 <= xMax && y1 >= yMin && y1 <= yMax && z1 >= zMin && z1 <= zMax
        let p2Inside = x2 >= xMin && x2 <= xMax && y2 >= yMin && y2 <= yMax && z2 >= zMin && z2 <= zMax

        if p1Inside && p2Inside {
            return edge
        }

        // Slow path: need to clip (unrolled and using pre-extracted bounds)
        var cx1 = x1, cy1 = y1, cz1 = z1
        var cx2 = x2, cy2 = y2, cz2 = z2

        // Clip X axis
        if cx1 < xMin {
            let t = (xMin - cx1) / (cx2 - cx1)
            cx1 = xMin
            cy1 = cy1 + t * (cy2 - cy1)
            cz1 = cz1 + t * (cz2 - cz1)
        } else if cx2 < xMin {
            let t = (xMin - cx1) / (cx2 - cx1)
            cx2 = xMin
            cy2 = cy1 + t * (cy2 - cy1)
            cz2 = cz1 + t * (cz2 - cz1)
        }
        if cx1 > xMax {
            let t = (xMax - cx1) / (cx2 - cx1)
            cx1 = xMax
            cy1 = cy1 + t * (cy2 - cy1)
            cz1 = cz1 + t * (cz2 - cz1)
        } else if cx2 > xMax {
            let t = (xMax - cx1) / (cx2 - cx1)
            cx2 = xMax
            cy2 = cy1 + t * (cy2 - cy1)
            cz2 = cz1 + t * (cz2 - cz1)
        }

        // Clip Y axis
        if cy1 < yMin {
            let t = (yMin - cy1) / (cy2 - cy1)
            cy1 = yMin
            cx1 = cx1 + t * (cx2 - cx1)
            cz1 = cz1 + t * (cz2 - cz1)
        } else if cy2 < yMin {
            let t = (yMin - cy1) / (cy2 - cy1)
            cy2 = yMin
            cx2 = cx1 + t * (cx2 - cx1)
            cz2 = cz1 + t * (cz2 - cz1)
        }
        if cy1 > yMax {
            let t = (yMax - cy1) / (cy2 - cy1)
            cy1 = yMax
            cx1 = cx1 + t * (cx2 - cx1)
            cz1 = cz1 + t * (cz2 - cz1)
        } else if cy2 > yMax {
            let t = (yMax - cy1) / (cy2 - cy1)
            cy2 = yMax
            cx2 = cx1 + t * (cx2 - cx1)
            cz2 = cz1 + t * (cz2 - cz1)
        }

        // Clip Z axis
        if cz1 < zMin {
            let t = (zMin - cz1) / (cz2 - cz1)
            cz1 = zMin
            cx1 = cx1 + t * (cx2 - cx1)
            cy1 = cy1 + t * (cy2 - cy1)
        } else if cz2 < zMin {
            let t = (zMin - cz1) / (cz2 - cz1)
            cz2 = zMin
            cx2 = cx1 + t * (cx2 - cx1)
            cy2 = cy1 + t * (cy2 - cy1)
        }
        if cz1 > zMax {
            let t = (zMax - cz1) / (cz2 - cz1)
            cz1 = zMax
            cx1 = cx1 + t * (cx2 - cx1)
            cy1 = cy1 + t * (cy2 - cy1)
        } else if cz2 > zMax {
            let t = (zMax - cz1) / (cz2 - cz1)
            cz2 = zMax
            cx2 = cx1 + t * (cx2 - cx1)
            cy2 = cy1 + t * (cy2 - cy1)
        }

        return Edge(Vector3(cx1, cy1, cz1), Vector3(cx2, cy2, cz2))
    }
}
