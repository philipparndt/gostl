import Metal
import simd

/// GPU-ready data for rendering measurements using instanced cylinders
final class MeasurementRenderData {
    let device: MTLDevice

    // Cylinder geometry (shared for all lines)
    let cylinderVertexBuffer: MTLBuffer
    let cylinderIndexBuffer: MTLBuffer
    let indexCount: Int

    // Preview cylinder geometry (green translucent)
    let previewCylinderVertexBuffer: MTLBuffer

    // Instance buffers
    var lineInstanceBuffer: MTLBuffer?
    var previewLineInstanceBuffer: MTLBuffer?
    var pointBuffer: MTLBuffer?
    var hoverBuffer: MTLBuffer?

    // Counts
    var lineInstanceCount: Int = 0
    var previewLineInstanceCount: Int = 0
    var pointCount: Int = 0
    var hoverVertexCount: Int = 0

    init(device: MTLDevice, thickness: Float) throws {
        self.device = device

        // Create unit cylinder geometry (along Y-axis, from 0 to 1)
        // Use 3x the thickness of wireframe for better visibility
        let cylinderGeometry = Self.createCylinderGeometry(
            radius: thickness * 3.0,
            segments: 8,
            color: SIMD4<Float>(1.0, 1.0, 0.0, 1.0) // Yellow
        )
        self.indexCount = cylinderGeometry.indices.count

        // Create vertex buffer for cylinder
        let vertexSize = cylinderGeometry.vertices.count * MemoryLayout<VertexIn>.stride
        guard let vertexBuffer = device.makeBuffer(bytes: cylinderGeometry.vertices, length: vertexSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.cylinderVertexBuffer = vertexBuffer

        // Create index buffer for cylinder (shared by both regular and preview)
        let indexSize = cylinderGeometry.indices.count * MemoryLayout<UInt16>.stride
        guard let indexBuffer = device.makeBuffer(bytes: cylinderGeometry.indices, length: indexSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.cylinderIndexBuffer = indexBuffer

        // Create preview cylinder with green color
        let previewCylinderGeometry = Self.createCylinderGeometry(
            radius: thickness * 3.0,
            segments: 8,
            color: SIMD4<Float>(0.5, 1.0, 0.5, 1.0) // Bright green
        )
        let previewVertexSize = previewCylinderGeometry.vertices.count * MemoryLayout<VertexIn>.stride
        guard let previewVertexBuffer = device.makeBuffer(bytes: previewCylinderGeometry.vertices, length: previewVertexSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.previewCylinderVertexBuffer = previewVertexBuffer
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

    // MARK: - Point Rendering

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

    // MARK: - Line Rendering (Instanced Cylinders)

    /// Create instance matrices for measurement lines
    private func updateLines(_ measurementSystem: MeasurementSystem) {
        var lineEdges: [Edge] = []
        var previewEdges: [Edge] = []

        // Lines for current measurement
        if measurementSystem.currentPoints.count >= 2 {
            for i in 0..<(measurementSystem.currentPoints.count - 1) {
                let p1 = measurementSystem.currentPoints[i].position
                let p2 = measurementSystem.currentPoints[i + 1].position
                lineEdges.append(Edge(p1, p2))
            }
        }

        // Lines for completed measurements
        for measurement in measurementSystem.measurements {
            if measurement.points.count >= 2 {
                for i in 0..<(measurement.points.count - 1) {
                    let p1 = measurement.points[i].position
                    let p2 = measurement.points[i + 1].position
                    lineEdges.append(Edge(p1, p2))
                }

                // For radius measurements, show all three points connected
                if measurement.type == .radius && measurement.points.count == 3 {
                    let p1 = measurement.points[2].position
                    let p2 = measurement.points[0].position
                    lineEdges.append(Edge(p1, p2))
                }
            }
        }

        // Preview line from last current point to hover
        if let hoverPoint = measurementSystem.hoverPoint,
           !measurementSystem.currentPoints.isEmpty {
            let lastPoint = measurementSystem.currentPoints.last!.position
            let hoverPos = hoverPoint.position
            previewEdges.append(Edge(lastPoint, hoverPos))
        }

        // Create instance buffers
        if !lineEdges.isEmpty {
            let instances = Self.createInstanceMatrices(edges: lineEdges)
            let instanceSize = instances.count * MemoryLayout<simd_float4x4>.stride
            lineInstanceBuffer = device.makeBuffer(bytes: instances, length: instanceSize, options: [])
            lineInstanceCount = instances.count
        } else {
            lineInstanceBuffer = nil
            lineInstanceCount = 0
        }

        if !previewEdges.isEmpty {
            let instances = Self.createInstanceMatrices(edges: previewEdges)
            let instanceSize = instances.count * MemoryLayout<simd_float4x4>.stride
            previewLineInstanceBuffer = device.makeBuffer(bytes: instances, length: instanceSize, options: [])
            previewLineInstanceCount = instances.count
        } else {
            previewLineInstanceBuffer = nil
            previewLineInstanceCount = 0
        }
    }

    // MARK: - Cylinder Geometry

    private static func createCylinderGeometry(radius: Float, segments: Int, color: SIMD4<Float>) -> (vertices: [VertexIn], indices: [UInt16]) {
        var vertices: [VertexIn] = []
        var indices: [UInt16] = []

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

    // MARK: - Cube Geometry (for Points)

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
}
