import Metal
import simd

/// GPU-ready data for rendering measurements (points, lines, hover)
final class MeasurementRenderData {
    let device: MTLDevice
    var pointBuffer: MTLBuffer?
    var lineBuffer: MTLBuffer?
    var hoverBuffer: MTLBuffer?
    var pointCount: Int = 0
    var lineVertexCount: Int = 0
    var hoverVertexCount: Int = 0

    init(device: MTLDevice) {
        self.device = device
    }

    /// Update buffers based on measurement system state
    func update(measurementSystem: MeasurementSystem) {
        // Clear hover if not collecting
        if !measurementSystem.isCollecting {
            hoverBuffer = nil
            hoverVertexCount = 0
        }

        // Update hover point
        if let hoverPoint = measurementSystem.hoverPoint {
            updateHoverPoint(hoverPoint)
        } else {
            hoverBuffer = nil
            hoverVertexCount = 0
        }

        // Update current measurement points
        var allPoints: [MeasurementPoint] = measurementSystem.currentPoints

        // Add completed measurement points
        for measurement in measurementSystem.measurements {
            allPoints.append(contentsOf: measurement.points)
        }

        // Create point markers
        updatePoints(allPoints)

        // Create lines for measurements
        updateLines(measurementSystem)
    }

    /// Create small cube marker for a point
    private func updatePoints(_ points: [MeasurementPoint]) {
        guard !points.isEmpty else {
            pointBuffer = nil
            pointCount = 0
            return
        }

        let size: Float = 0.5 // Small marker size
        var vertices: [VertexIn] = []

        for point in points {
            let pos = point.position.float3
            let color = SIMD4<Float>(1.0, 0.3, 0.3, 1.0) // Red for measurement points

            // Create a small cube at the point
            vertices.append(contentsOf: createCube(center: pos, size: size, color: color))
        }

        pointCount = vertices.count
        let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
        pointBuffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: [])
    }

    /// Create hover point marker
    private func updateHoverPoint(_ point: MeasurementPoint) {
        let size: Float = 0.6 // Slightly larger for hover
        let pos = point.position.float3
        let color = SIMD4<Float>(0.3, 1.0, 0.3, 1.0) // Green for hover

        let vertices = createCube(center: pos, size: size, color: color)
        hoverVertexCount = vertices.count
        let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
        hoverBuffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: [])
    }

    /// Create lines for measurements
    private func updateLines(_ measurementSystem: MeasurementSystem) {
        var vertices: [VertexIn] = []
        let lineColor = SIMD4<Float>(1.0, 1.0, 0.0, 1.0) // Yellow for measurement lines

        // Lines for current measurement
        if measurementSystem.currentPoints.count >= 2 {
            for i in 0..<(measurementSystem.currentPoints.count - 1) {
                let p1 = measurementSystem.currentPoints[i].position.float3
                let p2 = measurementSystem.currentPoints[i + 1].position.float3
                vertices.append(contentsOf: createLine(from: p1, to: p2, color: lineColor))
            }
        }

        // Lines for completed measurements
        for measurement in measurementSystem.measurements {
            if measurement.points.count >= 2 {
                for i in 0..<(measurement.points.count - 1) {
                    let p1 = measurement.points[i].position.float3
                    let p2 = measurement.points[i + 1].position.float3
                    vertices.append(contentsOf: createLine(from: p1, to: p2, color: lineColor))
                }

                // For angle measurements, also connect last to first
                if measurement.type == .angle && measurement.points.count == 3 {
                    // Don't connect - angle is shown by two lines meeting at middle point
                }

                // For radius measurements, show all three points connected
                if measurement.type == .radius && measurement.points.count == 3 {
                    let p1 = measurement.points[2].position.float3
                    let p2 = measurement.points[0].position.float3
                    vertices.append(contentsOf: createLine(from: p1, to: p2, color: lineColor))
                }
            }
        }

        // Line from last current point to hover (preview)
        if let hoverPoint = measurementSystem.hoverPoint,
           !measurementSystem.currentPoints.isEmpty {
            let lastPoint = measurementSystem.currentPoints.last!.position.float3
            let hoverPos = hoverPoint.position.float3
            let previewColor = SIMD4<Float>(0.5, 1.0, 0.5, 0.5) // Translucent green
            vertices.append(contentsOf: createLine(from: lastPoint, to: hoverPos, color: previewColor))
        }

        lineVertexCount = vertices.count
        if !vertices.isEmpty {
            let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
            lineBuffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: [])
        } else {
            lineBuffer = nil
        }
    }

    /// Create cube vertices
    private func createCube(center: SIMD3<Float>, size: Float, color: SIMD4<Float>) -> [VertexIn] {
        let half = size / 2.0
        var vertices: [VertexIn] = []

        // Simple cube (6 faces, 2 triangles each = 36 vertices)
        let positions: [SIMD3<Float>] = [
            // Front face
            center + SIMD3(-half, -half, half), center + SIMD3(half, -half, half), center + SIMD3(half, half, half),
            center + SIMD3(-half, -half, half), center + SIMD3(half, half, half), center + SIMD3(-half, half, half),
            // Back face
            center + SIMD3(-half, -half, -half), center + SIMD3(-half, half, -half), center + SIMD3(half, half, -half),
            center + SIMD3(-half, -half, -half), center + SIMD3(half, half, -half), center + SIMD3(half, -half, -half),
            // Top face
            center + SIMD3(-half, half, -half), center + SIMD3(-half, half, half), center + SIMD3(half, half, half),
            center + SIMD3(-half, half, -half), center + SIMD3(half, half, half), center + SIMD3(half, half, -half),
            // Bottom face
            center + SIMD3(-half, -half, -half), center + SIMD3(half, -half, -half), center + SIMD3(half, -half, half),
            center + SIMD3(-half, -half, -half), center + SIMD3(half, -half, half), center + SIMD3(-half, -half, half),
            // Right face
            center + SIMD3(half, -half, -half), center + SIMD3(half, half, -half), center + SIMD3(half, half, half),
            center + SIMD3(half, -half, -half), center + SIMD3(half, half, half), center + SIMD3(half, -half, half),
            // Left face
            center + SIMD3(-half, -half, -half), center + SIMD3(-half, -half, half), center + SIMD3(-half, half, half),
            center + SIMD3(-half, -half, -half), center + SIMD3(-half, half, half), center + SIMD3(-half, half, -half),
        ]

        for pos in positions {
            vertices.append(VertexIn(
                position: pos,
                normal: SIMD3(0, 1, 0), // Simple normal
                color: color
            ))
        }

        return vertices
    }

    /// Create line vertices (as a thin box/tube)
    private func createLine(from p1: SIMD3<Float>, to p2: SIMD3<Float>, color: SIMD4<Float>) -> [VertexIn] {
        let thickness: Float = 0.3 // Line thickness
        var vertices: [VertexIn] = []

        // Create a box along the line direction
        let dir = simd_normalize(p2 - p1)

        // Find perpendicular vectors to create box cross-section
        let perpendicular = abs(dir.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let right = simd_normalize(simd_cross(dir, perpendicular)) * (thickness / 2.0)
        let up = simd_normalize(simd_cross(right, dir)) * (thickness / 2.0)

        // 8 corners of the box (4 at each end)
        // End 1 (at p1)
        let c0 = p1 - right - up  // bottom-left
        let c1 = p1 + right - up  // bottom-right
        let c2 = p1 + right + up  // top-right
        let c3 = p1 - right + up  // top-left

        // End 2 (at p2)
        let c4 = p2 - right - up  // bottom-left
        let c5 = p2 + right - up  // bottom-right
        let c6 = p2 + right + up  // top-right
        let c7 = p2 - right + up  // top-left

        // Helper function to add a quad (2 triangles)
        func addQuad(_ v0: SIMD3<Float>, _ v1: SIMD3<Float>, _ v2: SIMD3<Float>, _ v3: SIMD3<Float>, normal: SIMD3<Float>) {
            // First triangle
            vertices.append(VertexIn(position: v0, normal: normal, color: color))
            vertices.append(VertexIn(position: v1, normal: normal, color: color))
            vertices.append(VertexIn(position: v2, normal: normal, color: color))
            // Second triangle
            vertices.append(VertexIn(position: v0, normal: normal, color: color))
            vertices.append(VertexIn(position: v2, normal: normal, color: color))
            vertices.append(VertexIn(position: v3, normal: normal, color: color))
        }

        // Create all 6 faces of the box

        // Bottom face (corners 0,1,5,4)
        addQuad(c0, c1, c5, c4, normal: -up / (thickness / 2.0))

        // Top face (corners 3,2,6,7)
        addQuad(c3, c7, c6, c2, normal: up / (thickness / 2.0))

        // Left face (corners 0,4,7,3)
        addQuad(c0, c4, c7, c3, normal: -right / (thickness / 2.0))

        // Right face (corners 1,2,6,5)
        addQuad(c1, c2, c6, c5, normal: right / (thickness / 2.0))

        // Front face (at p1: corners 0,1,2,3)
        addQuad(c0, c3, c2, c1, normal: -dir)

        // Back face (at p2: corners 4,5,6,7)
        addQuad(c4, c5, c6, c7, normal: dir)

        return vertices
    }
}
