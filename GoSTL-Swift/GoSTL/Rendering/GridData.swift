import Metal
import simd

/// GPU-ready grid data for spatial reference
final class GridData {
    let vertexBuffer: MTLBuffer
    let vertexCount: Int

    init(device: MTLDevice, size: Float = 100.0, spacing: Float = 10.0) throws {
        // Generate grid lines on XZ plane (Y = 0)
        let vertices = GridData.createGridLines(size: size, spacing: spacing)
        self.vertexCount = vertices.count

        // Create GPU buffer
        let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
        guard let buffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.vertexBuffer = buffer
    }

    // MARK: - Grid Generation

    private static func createGridLines(size: Float, spacing: Float) -> [VertexIn] {
        var vertices: [VertexIn] = []

        let halfSize = size / 2.0
        let lineCount = Int(size / spacing)

        // Grid colors
        let majorColor = SIMD4<Float>(0.3, 0.3, 0.3, 1.0) // Lighter gray for major lines
        let minorColor = SIMD4<Float>(0.2, 0.2, 0.2, 1.0) // Darker gray for minor lines

        // Lines parallel to X-axis (running along Z)
        for i in -lineCount...lineCount {
            let z = Float(i) * spacing
            let isMajorLine = i % 5 == 0 // Every 5th line is major
            let color = isMajorLine ? majorColor : minorColor

            vertices.append(VertexIn(
                position: SIMD3(-halfSize, 0, z),
                normal: SIMD3(0, 1, 0),
                color: color
            ))
            vertices.append(VertexIn(
                position: SIMD3(halfSize, 0, z),
                normal: SIMD3(0, 1, 0),
                color: color
            ))
        }

        // Lines parallel to Z-axis (running along X)
        for i in -lineCount...lineCount {
            let x = Float(i) * spacing
            let isMajorLine = i % 5 == 0
            let color = isMajorLine ? majorColor : minorColor

            vertices.append(VertexIn(
                position: SIMD3(x, 0, -halfSize),
                normal: SIMD3(0, 1, 0),
                color: color
            ))
            vertices.append(VertexIn(
                position: SIMD3(x, 0, halfSize),
                normal: SIMD3(0, 1, 0),
                color: color
            ))
        }

        return vertices
    }

    /// Update grid based on camera distance for adaptive spacing
    static func calculateAdaptiveSpacing(cameraDistance: Double) -> Float {
        // Adaptive grid spacing based on camera distance
        let distance = Float(cameraDistance)

        if distance < 10 {
            return 1.0
        } else if distance < 50 {
            return 5.0
        } else if distance < 200 {
            return 10.0
        } else if distance < 500 {
            return 25.0
        } else {
            return 50.0
        }
    }
}
