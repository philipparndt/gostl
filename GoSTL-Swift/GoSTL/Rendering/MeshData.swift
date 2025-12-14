import Metal
import simd

/// Thread-safe array wrapper for parallel writes to different indices
private final class ParallelArray<T>: @unchecked Sendable {
    var storage: [T]
    init(_ array: [T]) { self.storage = array }
    subscript(index: Int) -> T {
        get { storage[index] }
        set { storage[index] = newValue }
    }
}

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
        let triangleCount = model.triangleCount
        let vertexCount = triangleCount * 3

        // For small models, use sequential approach
        if triangleCount < 10000 {
            return createVerticesSequential(from: model)
        }

        // For large models, use parallel approach
        // Pre-allocate array with placeholder vertices
        let vertices = ParallelArray([VertexIn](repeating: VertexIn(position: .zero, normal: .zero, color: .zero), count: vertexCount))

        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let chunkSize = max(1000, triangleCount / processorCount)

        DispatchQueue.concurrentPerform(iterations: (triangleCount + chunkSize - 1) / chunkSize) { chunkIndex in
            let startTriangle = chunkIndex * chunkSize
            let endTriangle = min(startTriangle + chunkSize, triangleCount)

            for i in startTriangle..<endTriangle {
                let triangle = model.triangles[i]
                let color = triangle.color?.simd4 ?? SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
                let normal = triangle.normal.float3

                let vertexIndex = i * 3
                vertices[vertexIndex] = VertexIn(position: triangle.v1.float3, normal: normal, color: color)
                vertices[vertexIndex + 1] = VertexIn(position: triangle.v2.float3, normal: normal, color: color)
                vertices[vertexIndex + 2] = VertexIn(position: triangle.v3.float3, normal: normal, color: color)
            }
        }

        return vertices.storage
    }

    private static func createVerticesSequential(from model: STLModel) -> [VertexIn] {
        var vertices: [VertexIn] = []
        vertices.reserveCapacity(model.triangleCount * 3)

        for triangle in model.triangles {
            let color = triangle.color?.simd4 ?? SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
            let normal = triangle.normal.float3

            vertices.append(VertexIn(position: triangle.v1.float3, normal: normal, color: color))
            vertices.append(VertexIn(position: triangle.v2.float3, normal: normal, color: color))
            vertices.append(VertexIn(position: triangle.v3.float3, normal: normal, color: color))
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
