import Metal
import simd

/// GPU-ready mesh data with pre-baked lighting
final class MeshData {
    let vertexBuffer: MTLBuffer
    let vertexCount: Int

    init(device: MTLDevice, model: STLModel) throws {
        // Calculate vertices with baked lighting
        let vertices = MeshData.createVertices(from: model)
        self.vertexCount = vertices.count

        // Guard against empty models (zero-length buffers are invalid in Metal)
        guard !vertices.isEmpty else {
            throw MetalError.bufferCreationFailed
        }

        // Create GPU buffer
        let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
        guard let buffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.vertexBuffer = buffer
    }

    // MARK: - Vertex Generation

    private static func createVertices(from model: STLModel) -> [VertexIn] {
        var vertices: [VertexIn] = []
        vertices.reserveCapacity(model.triangleCount * 3)

        for triangle in model.triangles {
            // Use triangle's color if available, otherwise default to white
            let color = triangle.color?.simd4 ?? SIMD4<Float>(1.0, 1.0, 1.0, 1.0)

            // Add three vertices (one per triangle vertex)
            vertices.append(VertexIn(
                position: triangle.v1.float3,
                normal: triangle.normal.float3,
                color: color
            ))
            vertices.append(VertexIn(
                position: triangle.v2.float3,
                normal: triangle.normal.float3,
                color: color
            ))
            vertices.append(VertexIn(
                position: triangle.v3.float3,
                normal: triangle.normal.float3,
                color: color
            ))
        }

        return vertices
    }

    // MARK: - Three-Light Shading

    /// Return white color for vertices (lighting now calculated in shader with material properties)
    private static func calculateLighting(normal: Vector3) -> SIMD4<Float> {
        // Return white color - lighting is now calculated dynamically in the shader
        // based on material properties (glossiness, base color, etc.)
        return SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
    }
}
