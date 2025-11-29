import Metal
import simd

/// GPU-ready data for rendering slice planes
final class SlicePlaneData {
    let vertexBuffer: MTLBuffer
    let vertexCount: Int

    init(device: MTLDevice, slicingState: SlicingState, modelCenter: Vector3, planeSize: Float) throws {
        var vertices: [VertexIn] = []

        // Axis colors (matching slicing panel)
        let axisColors: [SIMD4<Float>] = [
            SIMD4(1.0, 0.31, 0.31, 0.15),  // X - Red (semi-transparent)
            SIMD4(0.31, 1.0, 0.31, 0.15),  // Y - Green
            SIMD4(0.31, 0.47, 1.0, 0.15)   // Z - Blue
        ]

        let halfSize = planeSize / 2.0
        let center = modelCenter.float3

        // Create planes for each axis (min and max)
        for axis in 0..<3 {
            let color = axisColors[axis]

            // Min plane
            let minPos = Float(slicingState.bounds[axis][0])
            vertices.append(contentsOf: Self.createPlane(
                axis: axis,
                position: minPos,
                center: center,
                halfSize: halfSize,
                color: color
            ))

            // Max plane
            let maxPos = Float(slicingState.bounds[axis][1])
            vertices.append(contentsOf: Self.createPlane(
                axis: axis,
                position: maxPos,
                center: center,
                halfSize: halfSize,
                color: color
            ))
        }

        self.vertexCount = vertices.count

        // Create vertex buffer
        let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
        guard let buffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.vertexBuffer = buffer
    }

    /// Create a plane for a specific axis at a given position
    private static func createPlane(
        axis: Int,
        position: Float,
        center: SIMD3<Float>,
        halfSize: Float,
        color: SIMD4<Float>
    ) -> [VertexIn] {
        var vertices: [VertexIn] = []

        // Define plane vertices based on axis
        let (v1, v2, v3, v4, normal): (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)

        switch axis {
        case 0: // X axis (YZ plane)
            v1 = SIMD3(position, center.y - halfSize, center.z - halfSize)
            v2 = SIMD3(position, center.y + halfSize, center.z - halfSize)
            v3 = SIMD3(position, center.y + halfSize, center.z + halfSize)
            v4 = SIMD3(position, center.y - halfSize, center.z + halfSize)
            normal = SIMD3(1, 0, 0)

        case 1: // Y axis (XZ plane)
            v1 = SIMD3(center.x - halfSize, position, center.z - halfSize)
            v2 = SIMD3(center.x + halfSize, position, center.z - halfSize)
            v3 = SIMD3(center.x + halfSize, position, center.z + halfSize)
            v4 = SIMD3(center.x - halfSize, position, center.z + halfSize)
            normal = SIMD3(0, 1, 0)

        case 2: // Z axis (XY plane)
            v1 = SIMD3(center.x - halfSize, center.y - halfSize, position)
            v2 = SIMD3(center.x + halfSize, center.y - halfSize, position)
            v3 = SIMD3(center.x + halfSize, center.y + halfSize, position)
            v4 = SIMD3(center.x - halfSize, center.y + halfSize, position)
            normal = SIMD3(0, 0, 1)

        default:
            fatalError("Invalid axis: \(axis)")
        }

        // Create two triangles for the quad
        // Triangle 1: v1, v2, v3
        vertices.append(VertexIn(position: v1, normal: normal, color: color))
        vertices.append(VertexIn(position: v2, normal: normal, color: color))
        vertices.append(VertexIn(position: v3, normal: normal, color: color))

        // Triangle 2: v1, v3, v4
        vertices.append(VertexIn(position: v1, normal: normal, color: color))
        vertices.append(VertexIn(position: v3, normal: normal, color: color))
        vertices.append(VertexIn(position: v4, normal: normal, color: color))

        return vertices
    }
}
