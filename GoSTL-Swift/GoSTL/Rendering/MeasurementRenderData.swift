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
    var constraintLineInstanceBuffer: MTLBuffer?  // Red line from constrained point to snap point
    var pointBuffer: MTLBuffer?
    var hoverBuffer: MTLBuffer?
    var constrainedPointBuffer: MTLBuffer?  // Yellow marker at constrained endpoint
    var radiusCircleInstanceBuffer: MTLBuffer?
    var radiusCenterBuffer: MTLBuffer?

    // Counts
    var lineInstanceCount: Int = 0
    var previewLineInstanceCount: Int = 0
    var constraintLineInstanceCount: Int = 0
    var pointCount: Int = 0
    var hoverVertexCount: Int = 0
    var constrainedPointVertexCount: Int = 0
    var radiusCircleInstanceCount: Int = 0
    var radiusCenterVertexCount: Int = 0

    // Radius circle cylinder geometry
    let radiusCircleCylinderVertexBuffer: MTLBuffer

    // Constraint line cylinder geometry (red)
    let constraintCylinderVertexBuffer: MTLBuffer

    init(device: MTLDevice, thickness: Float) throws {
        self.device = device

        // Measurement line thickness multiplier (relative to wireframe thickness)
        let measurementThickness: Float = 6.0

        // Create unit cylinder geometry (along Y-axis, from 0 to 1)
        let cylinderGeometry = Self.createCylinderGeometry(
            radius: thickness * measurementThickness,
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
            radius: thickness * measurementThickness,
            segments: 8,
            color: SIMD4<Float>(0.5, 1.0, 0.5, 1.0) // Bright green
        )
        let previewVertexSize = previewCylinderGeometry.vertices.count * MemoryLayout<VertexIn>.stride
        guard let previewVertexBuffer = device.makeBuffer(bytes: previewCylinderGeometry.vertices, length: previewVertexSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.previewCylinderVertexBuffer = previewVertexBuffer

        // Create radius circle cylinder with magenta color (slightly thicker than measurement lines)
        let radiusCircleCylinderGeometry = Self.createCylinderGeometry(
            radius: thickness * measurementThickness * 1.2,
            segments: 8,
            color: SIMD4<Float>(1.0, 0.59, 1.0, 0.78) // Magenta with transparency
        )
        let radiusCircleVertexSize = radiusCircleCylinderGeometry.vertices.count * MemoryLayout<VertexIn>.stride
        guard let radiusCircleVertexBuffer = device.makeBuffer(bytes: radiusCircleCylinderGeometry.vertices, length: radiusCircleVertexSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.radiusCircleCylinderVertexBuffer = radiusCircleVertexBuffer

        // Create constraint line cylinder with red color (for showing offset from constrained point to snap point)
        let constraintCylinderGeometry = Self.createCylinderGeometry(
            radius: thickness * measurementThickness,
            segments: 8,
            color: SIMD4<Float>(1.0, 0.0, 0.0, 1.0) // Red
        )
        let constraintVertexSize = constraintCylinderGeometry.vertices.count * MemoryLayout<VertexIn>.stride
        guard let constraintVertexBuffer = device.makeBuffer(bytes: constraintCylinderGeometry.vertices, length: constraintVertexSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.constraintCylinderVertexBuffer = constraintVertexBuffer
    }

    /// Update buffers based on measurement system state
    func update(measurementSystem: MeasurementSystem) {
        // Clear hover if not collecting
        if !measurementSystem.isCollecting {
            hoverBuffer = nil
            hoverVertexCount = 0
            constraintLineInstanceBuffer = nil
            constraintLineInstanceCount = 0
            constrainedPointBuffer = nil
            constrainedPointVertexCount = 0
        }

        // Update hover point
        if let hoverPoint = measurementSystem.hoverPoint {
            updateHoverPoint(hoverPoint)
        } else {
            hoverBuffer = nil
            hoverVertexCount = 0
        }

        // Update constrained point marker and constraint line
        updateConstrainedVisualization(measurementSystem)

        // Create point markers (pass measurement system to determine colors/sizes)
        updatePoints(measurementSystem)

        // Create lines for measurements
        updateLines(measurementSystem)

        // Create radius circles
        updateRadiusCircles(measurementSystem)
    }

    /// Update visualization for axis-constrained measurement
    private func updateConstrainedVisualization(_ measurementSystem: MeasurementSystem) {
        guard let constrainedEndpoint = measurementSystem.constrainedEndpoint,
              let hoverPoint = measurementSystem.hoverPoint,
              measurementSystem.constraint != nil else {
            constraintLineInstanceBuffer = nil
            constraintLineInstanceCount = 0
            constrainedPointBuffer = nil
            constrainedPointVertexCount = 0
            return
        }

        // Create red line from constrained endpoint to actual snap point (hover point)
        let constraintEdge = Edge(constrainedEndpoint, hoverPoint.position)
        let instances = Self.createInstanceMatrices(edges: [constraintEdge])
        let instanceSize = instances.count * MemoryLayout<simd_float4x4>.stride
        constraintLineInstanceBuffer = device.makeBuffer(bytes: instances, length: instanceSize, options: [])
        constraintLineInstanceCount = instances.count

        // Create yellow marker at constrained endpoint
        let markerColor = SIMD4<Float>(1.0, 1.0, 0.0, 1.0) // Yellow
        let vertices = createCube(center: constrainedEndpoint.float3, size: 0.5, color: markerColor)
        constrainedPointVertexCount = vertices.count
        let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
        constrainedPointBuffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: [])
    }

    // MARK: - Point Rendering

    /// Create small cube marker for a point
    private func updatePoints(_ measurementSystem: MeasurementSystem) {
        var vertices: [VertexIn] = []

        // Add current measurement points (in progress)
        let defaultSize: Float = 0.5
        let defaultColor = SIMD4<Float>(1.0, 0.3, 0.3, 1.0) // Red for regular measurement points

        for point in measurementSystem.currentPoints {
            let pos = point.position.float3
            let size = measurementSystem.mode == .radius ? Float(0.3) : defaultSize
            let color = measurementSystem.mode == .radius ? SIMD4<Float>(1.0, 0.59, 1.0, 1.0) : defaultColor // Same magenta as circle line
            vertices.append(contentsOf: createCube(center: pos, size: size, color: color))
        }

        // Add completed measurement points
        for measurement in measurementSystem.measurements {
            for point in measurement.points {
                let pos = point.position.float3
                let size = measurement.type == .radius ? Float(0.3) : defaultSize
                let color = measurement.type == .radius ? SIMD4<Float>(1.0, 0.59, 1.0, 1.0) : defaultColor // Same magenta as circle line
                vertices.append(contentsOf: createCube(center: pos, size: size, color: color))
            }
        }

        if !vertices.isEmpty {
            pointCount = vertices.count
            let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
            pointBuffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: [])
        } else {
            pointBuffer = nil
            pointCount = 0
        }
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

        // Lines for completed measurements (excluding radius measurements)
        for measurement in measurementSystem.measurements {
            // Skip radius measurements - they will be rendered as circles
            if measurement.type == .radius {
                continue
            }

            if measurement.points.count >= 2 {
                for i in 0..<(measurement.points.count - 1) {
                    let p1 = measurement.points[i].position
                    let p2 = measurement.points[i + 1].position
                    lineEdges.append(Edge(p1, p2))
                }
            }
        }

        // Preview line from last current point to hover (or constrained endpoint)
        if !measurementSystem.currentPoints.isEmpty {
            let lastPoint = measurementSystem.currentPoints.last!.position

            // If constraint is active, draw preview line to constrained endpoint (yellow line)
            // The red line from constrained endpoint to snap point is handled separately
            if let constrainedEndpoint = measurementSystem.constrainedEndpoint,
               measurementSystem.constraint != nil {
                previewEdges.append(Edge(lastPoint, constrainedEndpoint))
            } else if let hoverPoint = measurementSystem.hoverPoint {
                // Normal mode: draw line directly to hover point
                previewEdges.append(Edge(lastPoint, hoverPoint.position))
            }
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

    // MARK: - Radius Circle Rendering

    /// Update radius circle rendering data
    private func updateRadiusCircles(_ measurementSystem: MeasurementSystem) {
        var circleEdges: [Edge] = []
        var centerVertices: [VertexIn] = []

        // Process completed radius measurements
        for measurement in measurementSystem.measurements {
            guard measurement.type == .radius,
                  let circle = measurement.circle else {
                continue
            }

            // Create circle arc as edges between adjacent points
            circleEdges.append(contentsOf: createCircleArcEdges(circle: circle))

            // Create center point marker (smoother sphere, very small)
            let centerColor = SIMD4<Float>(1.0, 0.59, 1.0, 1.0) // Same magenta as circle line (255, 150, 255, 255)
            centerVertices.append(contentsOf: createSmoothSphere(center: circle.center.float3, radius: 0.25, color: centerColor))
        }

        // Update circle instance buffer (using instanced cylinders like measurement lines)
        if !circleEdges.isEmpty {
            let instances = Self.createInstanceMatrices(edges: circleEdges)
            let instanceSize = instances.count * MemoryLayout<simd_float4x4>.stride
            radiusCircleInstanceBuffer = device.makeBuffer(bytes: instances, length: instanceSize, options: [])
            radiusCircleInstanceCount = instances.count
        } else {
            radiusCircleInstanceBuffer = nil
            radiusCircleInstanceCount = 0
        }

        // Update center buffer
        if !centerVertices.isEmpty {
            radiusCenterVertexCount = centerVertices.count
            let bufferSize = centerVertices.count * MemoryLayout<VertexIn>.stride
            radiusCenterBuffer = device.makeBuffer(bytes: centerVertices, length: bufferSize, options: [])
        } else {
            radiusCenterBuffer = nil
            radiusCenterVertexCount = 0
        }
    }

    /// Create a circle arc as edges for instanced cylinder rendering
    private func createCircleArcEdges(circle: Circle) -> [Edge] {
        var edges: [Edge] = []
        let segments = 64 // Same as Go version
        let radius = Float(circle.radius)
        let center = circle.center.float3
        let normal = circle.normal.float3

        // Create orthogonal basis vectors for the circle plane
        let (u, v) = createOrthogonalBasis(normal: normal)

        // Generate circle points
        var points: [SIMD3<Float>] = []
        for i in 0..<segments {
            let angle = Float(i) * 2.0 * .pi / Float(segments)
            let x = radius * cos(angle)
            let y = radius * sin(angle)
            let position = center + u * x + v * y
            points.append(position)
        }

        // Create edges between consecutive points
        for i in 0..<segments {
            let p1 = points[i]
            let p2 = points[(i + 1) % segments] // Wrap around to close the circle
            edges.append(Edge(
                Vector3(Double(p1.x), Double(p1.y), Double(p1.z)),
                Vector3(Double(p2.x), Double(p2.y), Double(p2.z))
            ))
        }

        return edges
    }

    /// Create orthogonal basis vectors perpendicular to a normal
    private func createOrthogonalBasis(normal: SIMD3<Float>) -> (u: SIMD3<Float>, v: SIMD3<Float>) {
        // Choose an arbitrary vector not parallel to normal
        let arbitrary: SIMD3<Float> = abs(normal.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        let u = simd_normalize(simd_cross(normal, arbitrary))
        let v = simd_cross(normal, u)
        return (u, v)
    }

    /// Create a smooth sphere using UV sphere approach
    private func createSmoothSphere(center: SIMD3<Float>, radius: Float, color: SIMD4<Float>) -> [VertexIn] {
        var vertices: [VertexIn] = []

        let latitudeBands = 16
        let longitudeBands = 16

        // Generate sphere vertices using latitude/longitude
        for lat in 0...latitudeBands {
            let theta = Float(lat) * .pi / Float(latitudeBands)
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)

            for lon in 0...longitudeBands {
                let phi = Float(lon) * 2.0 * .pi / Float(longitudeBands)
                let sinPhi = sin(phi)
                let cosPhi = cos(phi)

                let x = cosPhi * sinTheta
                let y = cosTheta
                let z = sinPhi * sinTheta

                let normal = SIMD3<Float>(x, y, z)
                let position = center + normal * radius

                // Create triangles (skip last row)
                if lat < latitudeBands && lon < longitudeBands {
                    // First triangle
                    vertices.append(VertexIn(position: position, normal: normal, color: color))

                    let theta2 = Float(lat + 1) * .pi / Float(latitudeBands)
                    let sinTheta2 = sin(theta2)
                    let cosTheta2 = cos(theta2)
                    let normal2 = SIMD3<Float>(cosPhi * sinTheta2, cosTheta2, sinPhi * sinTheta2)
                    let position2 = center + normal2 * radius
                    vertices.append(VertexIn(position: position2, normal: normal2, color: color))

                    let phi3 = Float(lon + 1) * 2.0 * .pi / Float(longitudeBands)
                    let sinPhi3 = sin(phi3)
                    let cosPhi3 = cos(phi3)
                    let normal3 = SIMD3<Float>(cosPhi3 * sinTheta, cosTheta, sinPhi3 * sinTheta)
                    let position3 = center + normal3 * radius
                    vertices.append(VertexIn(position: position3, normal: normal3, color: color))

                    // Second triangle
                    vertices.append(VertexIn(position: position2, normal: normal2, color: color))

                    let normal4 = SIMD3<Float>(cosPhi3 * sinTheta2, cosTheta2, sinPhi3 * sinTheta2)
                    let position4 = center + normal4 * radius
                    vertices.append(VertexIn(position: position4, normal: normal4, color: color))

                    vertices.append(VertexIn(position: position3, normal: normal3, color: color))
                }
            }
        }

        return vertices
    }
}
