import Metal
import simd

/// GPU-ready build plate visualization data
final class BuildPlateData {
    let vertexBuffer: MTLBuffer
    let vertexCount: Int
    let buildPlate: BuildPlate
    let orientation: BuildPlateOrientation

    /// Create build plate centered on model position
    init(device: MTLDevice, buildPlate: BuildPlate, orientation: BuildPlateOrientation, modelBoundingBox: BoundingBox?) throws {
        guard buildPlate != .off else {
            throw MetalError.bufferCreationFailed
        }

        self.buildPlate = buildPlate
        self.orientation = orientation

        let vertices: [VertexIn]
        switch orientation {
        case .bottom:
            vertices = Self.createBottomPlateVertices(buildPlate: buildPlate, modelBoundingBox: modelBoundingBox)
        case .back:
            vertices = Self.createBackPlateVertices(buildPlate: buildPlate, modelBoundingBox: modelBoundingBox)
        }

        self.vertexCount = vertices.count

        let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
        guard let buffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.vertexBuffer = buffer
    }

    // MARK: - Bottom Orientation (XZ plane, Y up)

    private static func createBottomPlateVertices(buildPlate: BuildPlate, modelBoundingBox: BoundingBox?) -> [VertexIn] {
        var vertices: [VertexIn] = []

        let dims = buildPlate.dimensions
        let halfWidth = dims.x / 2
        let halfDepth = dims.y / 2

        let centerX: Float
        let centerZ: Float
        let plateY: Float

        if let bbox = modelBoundingBox {
            centerX = Float(bbox.center.x)
            centerZ = Float(bbox.center.z)
            plateY = Float(bbox.min.y)
        } else {
            centerX = 0
            centerZ = 0
            plateY = 0
        }

        // Build plate surface
        let surfaceColor = SIMD4<Float>(0.12, 0.15, 0.22, 0.45)
        addSurfaceXZ(&vertices, centerX: centerX, centerZ: centerZ, y: plateY,
                    halfWidth: halfWidth, halfDepth: halfDepth, color: surfaceColor)

        // Grid lines
        addGridLinesXZ(&vertices, centerX: centerX, centerZ: centerZ, y: plateY,
                      halfWidth: halfWidth, halfDepth: halfDepth)

        // Frame outline
        let frameColor = SIMD4<Float>(0.35, 0.55, 0.85, 0.85)
        addFrameXZ(&vertices, centerX: centerX, centerZ: centerZ, y: plateY + 0.05,
                  halfWidth: halfWidth, halfDepth: halfDepth, color: frameColor)

        return vertices
    }

    // MARK: - Back Orientation (XY plane, Z forward)

    private static func createBackPlateVertices(buildPlate: BuildPlate, modelBoundingBox: BoundingBox?) -> [VertexIn] {
        var vertices: [VertexIn] = []

        let dims = buildPlate.dimensions
        let halfWidth = dims.x / 2
        let halfHeight = dims.y / 2

        let centerX: Float
        let centerY: Float
        let plateZ: Float

        if let bbox = modelBoundingBox {
            centerX = Float(bbox.center.x)
            centerY = Float(bbox.center.y)
            plateZ = Float(bbox.min.z)
        } else {
            centerX = 0
            centerY = 0
            plateZ = 0
        }

        // Build plate surface
        let surfaceColor = SIMD4<Float>(0.12, 0.15, 0.22, 0.45)
        addSurfaceXY(&vertices, centerX: centerX, centerY: centerY, z: plateZ,
                    halfWidth: halfWidth, halfHeight: halfHeight, color: surfaceColor)

        // Grid lines
        addGridLinesXY(&vertices, centerX: centerX, centerY: centerY, z: plateZ,
                      halfWidth: halfWidth, halfHeight: halfHeight)

        // Frame outline
        let frameColor = SIMD4<Float>(0.35, 0.55, 0.85, 0.85)
        addFrameXY(&vertices, centerX: centerX, centerY: centerY, z: plateZ + 0.05,
                  halfWidth: halfWidth, halfHeight: halfHeight, color: frameColor)

        return vertices
    }

    // MARK: - Surface

    private static func addSurfaceXZ(
        _ vertices: inout [VertexIn],
        centerX: Float, centerZ: Float, y: Float,
        halfWidth: Float, halfDepth: Float, color: SIMD4<Float>
    ) {
        let normal = SIMD3<Float>(0, 1, 0)
        let p0 = SIMD3<Float>(centerX - halfWidth, y, centerZ - halfDepth)
        let p1 = SIMD3<Float>(centerX + halfWidth, y, centerZ - halfDepth)
        let p2 = SIMD3<Float>(centerX + halfWidth, y, centerZ + halfDepth)
        let p3 = SIMD3<Float>(centerX - halfWidth, y, centerZ + halfDepth)

        vertices.append(VertexIn(position: p0, normal: normal, color: color))
        vertices.append(VertexIn(position: p1, normal: normal, color: color))
        vertices.append(VertexIn(position: p2, normal: normal, color: color))
        vertices.append(VertexIn(position: p0, normal: normal, color: color))
        vertices.append(VertexIn(position: p2, normal: normal, color: color))
        vertices.append(VertexIn(position: p3, normal: normal, color: color))
    }

    private static func addSurfaceXY(
        _ vertices: inout [VertexIn],
        centerX: Float, centerY: Float, z: Float,
        halfWidth: Float, halfHeight: Float, color: SIMD4<Float>
    ) {
        let normal = SIMD3<Float>(0, 0, 1)
        let p0 = SIMD3<Float>(centerX - halfWidth, centerY - halfHeight, z)
        let p1 = SIMD3<Float>(centerX + halfWidth, centerY - halfHeight, z)
        let p2 = SIMD3<Float>(centerX + halfWidth, centerY + halfHeight, z)
        let p3 = SIMD3<Float>(centerX - halfWidth, centerY + halfHeight, z)

        vertices.append(VertexIn(position: p0, normal: normal, color: color))
        vertices.append(VertexIn(position: p1, normal: normal, color: color))
        vertices.append(VertexIn(position: p2, normal: normal, color: color))
        vertices.append(VertexIn(position: p0, normal: normal, color: color))
        vertices.append(VertexIn(position: p2, normal: normal, color: color))
        vertices.append(VertexIn(position: p3, normal: normal, color: color))
    }

    // MARK: - Grid Lines

    private static func addGridLinesXZ(
        _ vertices: inout [VertexIn],
        centerX: Float, centerZ: Float, y: Float,
        halfWidth: Float, halfDepth: Float
    ) {
        let normal = SIMD3<Float>(0, 1, 0)
        let gridSpacing: Float = 10.0
        let majorEvery: Int = 5
        let lineColor = SIMD4<Float>(0.28, 0.38, 0.55, 0.35)
        let majorLineColor = SIMD4<Float>(0.32, 0.45, 0.62, 0.55)
        let lineWidth: Float = 0.12
        let majorLineWidth: Float = 0.22
        let lineY = y + 0.015

        // X-direction lines
        var lineIndex = 0
        var x = centerX - Float(Int(halfWidth / gridSpacing)) * gridSpacing
        while x <= centerX + halfWidth {
            if x >= centerX - halfWidth {
                let isMajor = lineIndex % majorEvery == 0
                addLineXZ(&vertices, from: SIMD3(x, lineY, centerZ - halfDepth),
                         to: SIMD3(x, lineY, centerZ + halfDepth),
                         width: isMajor ? majorLineWidth : lineWidth,
                         color: isMajor ? majorLineColor : lineColor, normal: normal)
            }
            x += gridSpacing
            lineIndex += 1
        }

        // Z-direction lines
        lineIndex = 0
        var z = centerZ - Float(Int(halfDepth / gridSpacing)) * gridSpacing
        while z <= centerZ + halfDepth {
            if z >= centerZ - halfDepth {
                let isMajor = lineIndex % majorEvery == 0
                addLineXZ(&vertices, from: SIMD3(centerX - halfWidth, lineY, z),
                         to: SIMD3(centerX + halfWidth, lineY, z),
                         width: isMajor ? majorLineWidth : lineWidth,
                         color: isMajor ? majorLineColor : lineColor, normal: normal)
            }
            z += gridSpacing
            lineIndex += 1
        }

        // Center crosshairs
        let crossColor = SIMD4<Float>(0.4, 0.55, 0.75, 0.7)
        let crossWidth: Float = 0.35
        let crossY = y + 0.025
        addLineXZ(&vertices, from: SIMD3(centerX - halfWidth, crossY, centerZ),
                 to: SIMD3(centerX + halfWidth, crossY, centerZ),
                 width: crossWidth, color: crossColor, normal: normal)
        addLineXZ(&vertices, from: SIMD3(centerX, crossY, centerZ - halfDepth),
                 to: SIMD3(centerX, crossY, centerZ + halfDepth),
                 width: crossWidth, color: crossColor, normal: normal)
    }

    private static func addGridLinesXY(
        _ vertices: inout [VertexIn],
        centerX: Float, centerY: Float, z: Float,
        halfWidth: Float, halfHeight: Float
    ) {
        let normal = SIMD3<Float>(0, 0, 1)
        let gridSpacing: Float = 10.0
        let majorEvery: Int = 5
        let lineColor = SIMD4<Float>(0.28, 0.38, 0.55, 0.35)
        let majorLineColor = SIMD4<Float>(0.32, 0.45, 0.62, 0.55)
        let lineWidth: Float = 0.12
        let majorLineWidth: Float = 0.22
        let lineZ = z + 0.015

        // X-direction lines
        var lineIndex = 0
        var x = centerX - Float(Int(halfWidth / gridSpacing)) * gridSpacing
        while x <= centerX + halfWidth {
            if x >= centerX - halfWidth {
                let isMajor = lineIndex % majorEvery == 0
                addLineXY(&vertices, from: SIMD3(x, centerY - halfHeight, lineZ),
                         to: SIMD3(x, centerY + halfHeight, lineZ),
                         width: isMajor ? majorLineWidth : lineWidth,
                         color: isMajor ? majorLineColor : lineColor, normal: normal)
            }
            x += gridSpacing
            lineIndex += 1
        }

        // Y-direction lines
        lineIndex = 0
        var yPos = centerY - Float(Int(halfHeight / gridSpacing)) * gridSpacing
        while yPos <= centerY + halfHeight {
            if yPos >= centerY - halfHeight {
                let isMajor = lineIndex % majorEvery == 0
                addLineXY(&vertices, from: SIMD3(centerX - halfWidth, yPos, lineZ),
                         to: SIMD3(centerX + halfWidth, yPos, lineZ),
                         width: isMajor ? majorLineWidth : lineWidth,
                         color: isMajor ? majorLineColor : lineColor, normal: normal)
            }
            yPos += gridSpacing
            lineIndex += 1
        }

        // Center crosshairs
        let crossColor = SIMD4<Float>(0.4, 0.55, 0.75, 0.7)
        let crossWidth: Float = 0.35
        let crossZ = z + 0.025
        addLineXY(&vertices, from: SIMD3(centerX - halfWidth, centerY, crossZ),
                 to: SIMD3(centerX + halfWidth, centerY, crossZ),
                 width: crossWidth, color: crossColor, normal: normal)
        addLineXY(&vertices, from: SIMD3(centerX, centerY - halfHeight, crossZ),
                 to: SIMD3(centerX, centerY + halfHeight, crossZ),
                 width: crossWidth, color: crossColor, normal: normal)
    }

    // MARK: - Frame

    private static func addFrameXZ(
        _ vertices: inout [VertexIn],
        centerX: Float, centerZ: Float, y: Float,
        halfWidth: Float, halfDepth: Float, color: SIMD4<Float>
    ) {
        let normal = SIMD3<Float>(0, 1, 0)
        let thickness: Float = max(0.6, min(halfWidth, halfDepth) * 0.005)

        // Four edges
        addLineXZ(&vertices, from: SIMD3(centerX - halfWidth, y, centerZ - halfDepth),
                 to: SIMD3(centerX + halfWidth, y, centerZ - halfDepth),
                 width: thickness, color: color, normal: normal)
        addLineXZ(&vertices, from: SIMD3(centerX - halfWidth, y, centerZ + halfDepth),
                 to: SIMD3(centerX + halfWidth, y, centerZ + halfDepth),
                 width: thickness, color: color, normal: normal)
        addLineXZ(&vertices, from: SIMD3(centerX - halfWidth, y, centerZ - halfDepth),
                 to: SIMD3(centerX - halfWidth, y, centerZ + halfDepth),
                 width: thickness, color: color, normal: normal)
        addLineXZ(&vertices, from: SIMD3(centerX + halfWidth, y, centerZ - halfDepth),
                 to: SIMD3(centerX + halfWidth, y, centerZ + halfDepth),
                 width: thickness, color: color, normal: normal)
    }

    private static func addFrameXY(
        _ vertices: inout [VertexIn],
        centerX: Float, centerY: Float, z: Float,
        halfWidth: Float, halfHeight: Float, color: SIMD4<Float>
    ) {
        let normal = SIMD3<Float>(0, 0, 1)
        let thickness: Float = max(0.6, min(halfWidth, halfHeight) * 0.005)

        // Four edges
        addLineXY(&vertices, from: SIMD3(centerX - halfWidth, centerY - halfHeight, z),
                 to: SIMD3(centerX + halfWidth, centerY - halfHeight, z),
                 width: thickness, color: color, normal: normal)
        addLineXY(&vertices, from: SIMD3(centerX - halfWidth, centerY + halfHeight, z),
                 to: SIMD3(centerX + halfWidth, centerY + halfHeight, z),
                 width: thickness, color: color, normal: normal)
        addLineXY(&vertices, from: SIMD3(centerX - halfWidth, centerY - halfHeight, z),
                 to: SIMD3(centerX - halfWidth, centerY + halfHeight, z),
                 width: thickness, color: color, normal: normal)
        addLineXY(&vertices, from: SIMD3(centerX + halfWidth, centerY - halfHeight, z),
                 to: SIMD3(centerX + halfWidth, centerY + halfHeight, z),
                 width: thickness, color: color, normal: normal)
    }

    // MARK: - Line Helpers

    private static func addLineXZ(
        _ vertices: inout [VertexIn],
        from start: SIMD3<Float>, to end: SIMD3<Float>,
        width: Float, color: SIMD4<Float>, normal: SIMD3<Float>
    ) {
        let dir = normalize(end - start)
        let perp = SIMD3<Float>(-dir.z, 0, dir.x) * width / 2

        let v0 = start - perp
        let v1 = start + perp
        let v2 = end + perp
        let v3 = end - perp

        vertices.append(VertexIn(position: v0, normal: normal, color: color))
        vertices.append(VertexIn(position: v1, normal: normal, color: color))
        vertices.append(VertexIn(position: v2, normal: normal, color: color))
        vertices.append(VertexIn(position: v0, normal: normal, color: color))
        vertices.append(VertexIn(position: v2, normal: normal, color: color))
        vertices.append(VertexIn(position: v3, normal: normal, color: color))
    }

    private static func addLineXY(
        _ vertices: inout [VertexIn],
        from start: SIMD3<Float>, to end: SIMD3<Float>,
        width: Float, color: SIMD4<Float>, normal: SIMD3<Float>
    ) {
        let dir = normalize(end - start)
        let perp = SIMD3<Float>(-dir.y, dir.x, 0) * width / 2

        let v0 = start - perp
        let v1 = start + perp
        let v2 = end + perp
        let v3 = end - perp

        vertices.append(VertexIn(position: v0, normal: normal, color: color))
        vertices.append(VertexIn(position: v1, normal: normal, color: color))
        vertices.append(VertexIn(position: v2, normal: normal, color: color))
        vertices.append(VertexIn(position: v0, normal: normal, color: color))
        vertices.append(VertexIn(position: v2, normal: normal, color: color))
        vertices.append(VertexIn(position: v3, normal: normal, color: color))
    }
}
