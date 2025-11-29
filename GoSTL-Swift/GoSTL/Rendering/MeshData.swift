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
            // Calculate lighting for this triangle
            let color = calculateLighting(normal: triangle.normal)

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

    /// Calculate pre-baked lighting using three-light setup
    /// Matches the Go version's lighting model
    private static func calculateLighting(normal: Vector3) -> SIMD4<Float> {
        let n = simd_normalize(normal.float3)

        // Three-light setup (normalized)
        let keyLight = simd_normalize(SIMD3<Float>(0.5, 1.0, 0.5))      // Main light
        let fillLight = simd_normalize(SIMD3<Float>(-0.5, 0.3, 0.8))   // Fill light
        let rimLight = simd_normalize(SIMD3<Float>(0.0, 0.5, -1.0))    // Rim light

        // Calculate diffuse lighting for each light
        let keyIntensity = max(0, simd_dot(n, keyLight)) * 0.6
        let fillIntensity = max(0, simd_dot(n, fillLight)) * 0.3
        let rimIntensity = max(0, simd_dot(n, rimLight)) * 0.2

        // Ambient + diffuse
        let ambient: Float = 0.3
        let totalLight = ambient + keyIntensity + fillIntensity + rimIntensity

        // Base color (light gray)
        let baseColor = SIMD3<Float>(0.5, 0.6, 1)
        let litColor = baseColor * min(1.0, totalLight)

        return SIMD4(litColor.x, litColor.y, litColor.z, 1.0)
    }
}

// MARK: - Metal Errors

extension MetalError {
    static let bufferCreationFailed = MetalError.pipelineCreationFailed
}
