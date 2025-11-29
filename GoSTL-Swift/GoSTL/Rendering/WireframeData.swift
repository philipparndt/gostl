import Metal
import simd

/// GPU-ready wireframe data for edge rendering using instanced cylinders
final class WireframeData {
    let cylinderVertexBuffer: MTLBuffer
    let cylinderIndexBuffer: MTLBuffer
    let instanceBuffer: MTLBuffer
    let indexCount: Int
    let instanceCount: Int

    init(device: MTLDevice, model: STLModel, thickness: Float = 0.005, sliceBounds: [[Double]]? = nil) throws {
        // Extract unique edges from model
        var edges = model.extractEdges()

        // If slicing, clip edges to bounds (preserving original edge directions)
        if let bounds = sliceBounds {
            edges = edges.compactMap { edge in
                Self.clipEdgeToBounds(edge, bounds: bounds)
            }
        }

        self.instanceCount = edges.count

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

        // Create instance buffer with transformation matrices for each edge
        let instances = WireframeData.createInstanceMatrices(edges: edges)
        let instanceSize = instances.count * MemoryLayout<simd_float4x4>.stride
        guard let instanceBuffer = device.makeBuffer(bytes: instances, length: instanceSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.instanceBuffer = instanceBuffer
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
    private static func clipEdgeToBounds(_ edge: Edge, bounds: [[Double]]) -> Edge? {
        let p1 = edge.start
        let p2 = edge.end

        // Fast path: check if edge is fully inside or fully outside bounds
        var p1Inside = true
        var p2Inside = true

        for axis in 0..<3 {
            let minBound = bounds[axis][0]
            let maxBound = bounds[axis][1]
            let coord1 = p1.component(axis: axis)
            let coord2 = p2.component(axis: axis)

            // Early rejection: both points outside on same side
            if (coord1 < minBound && coord2 < minBound) || (coord1 > maxBound && coord2 > maxBound) {
                return nil
            }

            // Check if points are inside
            if coord1 < minBound || coord1 > maxBound { p1Inside = false }
            if coord2 < minBound || coord2 > maxBound { p2Inside = false }
        }

        // Fast path: edge completely inside - no clipping needed
        if p1Inside && p2Inside {
            return edge
        }

        // Slow path: need to clip
        var clippedP1 = p1
        var clippedP2 = p2

        for axis in 0..<3 {
            let minBound = bounds[axis][0]
            let maxBound = bounds[axis][1]

            var coord1 = clippedP1.component(axis: axis)
            var coord2 = clippedP2.component(axis: axis)

            // Clip against min plane
            if coord1 < minBound {
                let t = (minBound - coord1) / (coord2 - coord1)
                clippedP1 = interpolate(clippedP1, clippedP2, t: t)
                coord1 = minBound
            } else if coord2 < minBound {
                let t = (minBound - coord1) / (coord2 - coord1)
                clippedP2 = interpolate(clippedP1, clippedP2, t: t)
                coord2 = minBound
            }

            // Clip against max plane
            coord1 = clippedP1.component(axis: axis)
            coord2 = clippedP2.component(axis: axis)

            if coord1 > maxBound {
                let t = (maxBound - coord1) / (coord2 - coord1)
                clippedP1 = interpolate(clippedP1, clippedP2, t: t)
            } else if coord2 > maxBound {
                let t = (maxBound - coord1) / (coord2 - coord1)
                clippedP2 = interpolate(clippedP1, clippedP2, t: t)
            }
        }

        return Edge(clippedP1, clippedP2)
    }

    /// Interpolate between two points
    private static func interpolate(_ p1: Vector3, _ p2: Vector3, t: Double) -> Vector3 {
        return Vector3(
            p1.x + t * (p2.x - p1.x),
            p1.y + t * (p2.y - p1.y),
            p1.z + t * (p2.z - p1.z)
        )
    }
}
