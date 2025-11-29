import Metal
import simd

/// GPU-ready data for rendering cut edges from slicing
final class CutEdgeData {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let instanceBuffer: MTLBuffer
    let vertexCount: Int
    let indexCount: Int
    let instanceCount: Int

    /// Axis colors for cut edges
    private static let axisColors: [SIMD4<Float>] = [
        SIMD4(1.0, 0.31, 0.31, 1.0),  // X - Red
        SIMD4(0.31, 1.0, 0.31, 1.0),  // Y - Green
        SIMD4(0.31, 0.47, 1.0, 1.0)   // Z - Blue
    ]

    init(device: MTLDevice, cutEdges: [CutEdge]) throws {
        guard !cutEdges.isEmpty else {
            throw MetalError.bufferCreationFailed
        }

        // Create unit cylinder geometry (radius = 1.0)
        // Thickness will be calculated dynamically in the shader for pixel-perfect rendering
        let cylinderGeometry = Self.createCylinderGeometry(radius: 1.0, segments: 8)
        self.vertexCount = cylinderGeometry.vertices.count
        self.indexCount = cylinderGeometry.indices.count

        // Create vertex buffer
        let vertexSize = cylinderGeometry.vertices.count * MemoryLayout<VertexIn>.stride
        guard let vBuffer = device.makeBuffer(bytes: cylinderGeometry.vertices, length: vertexSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.vertexBuffer = vBuffer

        // Create index buffer
        let indexSize = cylinderGeometry.indices.count * MemoryLayout<UInt16>.stride
        guard let iBuffer = device.makeBuffer(bytes: cylinderGeometry.indices, length: indexSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.indexBuffer = iBuffer

        // Create instance data (one transform matrix per edge, with color)
        var instances: [InstanceData] = []
        for edge in cutEdges {
            let instance = Self.createInstanceData(edge: edge)
            instances.append(instance)
        }

        self.instanceCount = instances.count

        // Create instance buffer
        let instanceSize = instances.count * MemoryLayout<InstanceData>.stride
        guard let instBuffer = device.makeBuffer(bytes: instances, length: instanceSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.instanceBuffer = instBuffer
    }

    /// Create instance data with color for a cut edge
    private static func createInstanceData(edge: CutEdge) -> InstanceData {
        let start = edge.start.float3
        let end = edge.end.float3
        let direction = end - start
        let length = simd_length(direction)

        // Avoid zero-length edges
        guard length > 0.0001 else {
            return InstanceData(modelMatrix: matrix_identity_float4x4, color: axisColors[edge.axis])
        }

        let normalizedDir = direction / length

        // Build transformation matrix
        // 1. Scale cylinder to edge length (cylinder is 0->1 along Y)
        let scale = simd_float4x4(diagonal: SIMD4(1.0, length, 1.0, 1.0))

        // 2. Rotate from Y-axis to edge direction
        let yAxis = SIMD3<Float>(0, 1, 0)
        let rotation = Self.rotationMatrix(from: yAxis, to: normalizedDir)

        // 3. Translate to start position
        var translation = matrix_identity_float4x4
        translation.columns.3 = SIMD4(start.x, start.y, start.z, 1.0)

        // Combine: translate * rotate * scale
        let modelMatrix = translation * rotation * scale

        return InstanceData(modelMatrix: modelMatrix, color: axisColors[edge.axis])
    }

    /// Create a rotation matrix that rotates vector 'from' to vector 'to'
    private static func rotationMatrix(from: SIMD3<Float>, to: SIMD3<Float>) -> simd_float4x4 {
        let axis = simd_cross(from, to)
        let axisLength = simd_length(axis)

        // Vectors are parallel or anti-parallel
        if axisLength < 0.0001 {
            // Check if they point in the same direction
            if simd_dot(from, to) > 0 {
                return matrix_identity_float4x4  // No rotation needed
            } else {
                // 180-degree rotation - use any perpendicular axis
                let perpendicular = abs(from.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
                let rotAxis = simd_normalize(simd_cross(from, perpendicular))
                return simd_float4x4(rotationAngle: .pi, axis: rotAxis)
            }
        }

        let normalizedAxis = axis / axisLength
        let angle = asin(axisLength)  // Angle between vectors

        return simd_float4x4(rotationAngle: angle, axis: normalizedAxis)
    }

    /// Create unit cylinder geometry along Y-axis (0 to 1)
    private static func createCylinderGeometry(radius: Float, segments: Int) -> (vertices: [VertexIn], indices: [UInt16]) {
        var vertices: [VertexIn] = []
        var indices: [UInt16] = []

        // Create two circles (bottom at y=0, top at y=1)
        for i in 0..<segments {
            let angle = Float(i) * 2.0 * .pi / Float(segments)
            let x = cos(angle) * radius
            let z = sin(angle) * radius

            // Bottom vertex
            let normalBottom = simd_normalize(SIMD3<Float>(x, 0, z))
            vertices.append(VertexIn(
                position: SIMD3<Float>(x, 0, z),
                normal: normalBottom,
                color: SIMD4<Float>(1, 1, 1, 1)  // Color will be overridden by instance data
            ))

            // Top vertex
            let normalTop = simd_normalize(SIMD3<Float>(x, 0, z))
            vertices.append(VertexIn(
                position: SIMD3<Float>(x, 1, z),
                normal: normalTop,
                color: SIMD4<Float>(1, 1, 1, 1)
            ))
        }

        // Create indices for cylinder sides (quads as two triangles)
        for i in 0..<segments {
            let current = UInt16(i * 2)
            let next = UInt16(((i + 1) % segments) * 2)

            // Bottom-left, bottom-right, top-right
            indices.append(current)
            indices.append(next)
            indices.append(next + 1)

            // Bottom-left, top-right, top-left
            indices.append(current)
            indices.append(next + 1)
            indices.append(current + 1)
        }

        return (vertices, indices)
    }
}

/// Instance data for rendering (same as wireframe but with color)
struct InstanceData {
    let modelMatrix: simd_float4x4
    let color: SIMD4<Float>
}

extension simd_float4x4 {
    init(rotationAngle angle: Float, axis: SIMD3<Float>) {
        let c = cos(angle)
        let s = sin(angle)
        let t = 1 - c
        let x = axis.x
        let y = axis.y
        let z = axis.z

        self.init(
            SIMD4<Float>(t*x*x + c,   t*x*y + z*s, t*x*z - y*s, 0),
            SIMD4<Float>(t*x*y - z*s, t*y*y + c,   t*y*z + x*s, 0),
            SIMD4<Float>(t*x*z + y*s, t*y*z - x*s, t*z*z + c,   0),
            SIMD4<Float>(0,           0,           0,           1)
        )
    }
}
