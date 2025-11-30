import Metal
import simd

/// GPU-ready grid data for spatial reference
final class GridData {
    let vertexBuffer: MTLBuffer
    let vertexCount: Int
    let gridSpacing: Float
    let bounds: GridBounds
    let mode: GridMode
    let dimensionLinesBuffer: MTLBuffer?
    let dimensionLinesCount: Int

    /// Grid bounds information for label rendering
    struct GridBounds {
        let minX: Float
        let maxX: Float
        let minY: Float
        let maxY: Float
        let minZ: Float
        let maxZ: Float
        let bottomY: Float
        let bboxMinX: Float
        let bboxMaxX: Float
        let bboxMinY: Float
        let bboxMaxY: Float
        let bboxMinZ: Float
        let bboxMaxZ: Float
    }

    init(device: MTLDevice, size: Float = 100.0, spacing: Float = 10.0) throws {
        // Generate simple centered grid for initial state
        let vertices = GridData.createSimpleGrid(size: size, spacing: spacing)
        self.vertexCount = vertices.count
        self.gridSpacing = spacing
        self.mode = .bottom
        self.bounds = GridBounds(
            minX: -size/2, maxX: size/2,
            minY: 0, maxY: size/2,
            minZ: -size/2, maxZ: size/2,
            bottomY: 0,
            bboxMinX: -size/2, bboxMaxX: size/2,
            bboxMinY: 0, bboxMaxY: size/2,
            bboxMinZ: -size/2, bboxMaxZ: size/2
        )
        self.dimensionLinesBuffer = nil
        self.dimensionLinesCount = 0

        // Create GPU buffer
        let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
        guard let buffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.vertexBuffer = buffer
    }

    init(device: MTLDevice, mode: GridMode, boundingBox: BoundingBox) throws {
        let padding: Float = 1.2
        var minX = Float(boundingBox.min.x) * padding
        var maxX = Float(boundingBox.max.x) * padding
        var minY = Float(boundingBox.min.y) * padding
        var maxY = Float(boundingBox.max.y) * padding
        var minZ = Float(boundingBox.min.z) * padding
        var maxZ = Float(boundingBox.max.z) * padding

        // Calculate grid spacing
        let spacing: Float
        if mode == .oneMM {
            spacing = 1.0
        } else {
            let sizeX = maxX - minX
            let sizeY = maxY - minY
            let sizeZ = maxZ - minZ
            let maxSize = max(sizeX, max(sizeY, sizeZ))
            spacing = GridData.calculateGridSpacing(size: maxSize)
        }
        self.gridSpacing = spacing

        // Snap grid bounds to spacing
        minX = floor(minX / spacing) * spacing
        maxX = ceil(maxX / spacing) * spacing
        minY = floor(minY / spacing) * spacing
        maxY = ceil(maxY / spacing) * spacing
        minZ = floor(minZ / spacing) * spacing
        maxZ = ceil(maxZ / spacing) * spacing

        self.mode = mode
        self.bounds = GridBounds(
            minX: minX, maxX: maxX,
            minY: minY, maxY: maxY,
            minZ: minZ, maxZ: maxZ,
            bottomY: Float(boundingBox.min.y),
            bboxMinX: Float(boundingBox.min.x),
            bboxMaxX: Float(boundingBox.max.x),
            bboxMinY: Float(boundingBox.min.y),
            bboxMaxY: Float(boundingBox.max.y),
            bboxMinZ: Float(boundingBox.min.z),
            bboxMaxZ: Float(boundingBox.max.z)
        )

        // Generate grid vertices based on mode
        var vertices: [VertexIn] = []
        let bottomY = Float(boundingBox.min.y)

        // Always draw bottom grid (XZ plane)
        GridData.addXZPlane(
            &vertices,
            minX: minX, maxX: maxX,
            minZ: minZ, maxZ: maxZ,
            y: bottomY,
            spacing: spacing,
            mode: mode
        )

        // Add additional planes for allSides and oneMM modes
        if mode == .allSides || mode == .oneMM {
            // Back wall (XY plane at min Z)
            GridData.addXYPlane(
                &vertices,
                minX: minX, maxX: maxX,
                minY: minY, maxY: maxY,
                z: minZ,
                spacing: spacing,
                mode: mode
            )

            // Left wall (YZ plane at min X)
            GridData.addYZPlane(
                &vertices,
                minY: minY, maxY: maxY,
                minZ: minZ, maxZ: maxZ,
                x: minX,
                spacing: spacing,
                mode: mode
            )
        }

        self.vertexCount = vertices.count

        // Create GPU buffer
        let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
        guard let buffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.vertexBuffer = buffer

        // Generate dimension lines
        let dimensionVertices = GridData.createDimensionLines(
            bboxMin: SIMD3(Float(boundingBox.min.x), Float(boundingBox.min.y), Float(boundingBox.min.z)),
            bboxMax: SIMD3(Float(boundingBox.max.x), Float(boundingBox.max.y), Float(boundingBox.max.z)),
            bottomY: bottomY
        )
        self.dimensionLinesCount = dimensionVertices.count

        if !dimensionVertices.isEmpty {
            let dimBufferSize = dimensionVertices.count * MemoryLayout<VertexIn>.stride
            self.dimensionLinesBuffer = device.makeBuffer(bytes: dimensionVertices, length: dimBufferSize, options: [])
        } else {
            self.dimensionLinesBuffer = nil
        }
    }

    // MARK: - Grid Generation

    private static func createSimpleGrid(size: Float, spacing: Float) -> [VertexIn] {
        var vertices: [VertexIn] = []
        let halfSize = size / 2.0
        let lineCount = Int(size / spacing)

        let majorColor = SIMD4<Float>(0.3, 0.3, 0.3, 1.0)
        let minorColor = SIMD4<Float>(0.2, 0.2, 0.2, 1.0)

        for i in -lineCount...lineCount {
            let z = Float(i) * spacing
            let isMajorLine = i % 5 == 0
            let color = isMajorLine ? majorColor : minorColor

            vertices.append(VertexIn(position: SIMD3(-halfSize, 0, z), normal: SIMD3(0, 1, 0), color: color))
            vertices.append(VertexIn(position: SIMD3(halfSize, 0, z), normal: SIMD3(0, 1, 0), color: color))
        }

        for i in -lineCount...lineCount {
            let x = Float(i) * spacing
            let isMajorLine = i % 5 == 0
            let color = isMajorLine ? majorColor : minorColor

            vertices.append(VertexIn(position: SIMD3(x, 0, -halfSize), normal: SIMD3(0, 1, 0), color: color))
            vertices.append(VertexIn(position: SIMD3(x, 0, halfSize), normal: SIMD3(0, 1, 0), color: color))
        }

        return vertices
    }

    private static func getLineColor(value: Float, spacing: Float, mode: GridMode) -> SIMD4<Float> {
        let gridColor = SIMD4<Float>(100.0/255.0, 100.0/255.0, 100.0/255.0, 160.0/255.0)
        let majorColor = SIMD4<Float>(140.0/255.0, 140.0/255.0, 140.0/255.0, 200.0/255.0)
        let superMajorColor = SIMD4<Float>(180.0/255.0, 180.0/255.0, 180.0/255.0, 240.0/255.0)

        if mode == .oneMM {
            // In 1mm mode: every 10mm is super major, every 5mm is major
            if abs(value.truncatingRemainder(dividingBy: 10.0)) < 0.001 {
                return superMajorColor
            } else if abs(value.truncatingRemainder(dividingBy: 5.0)) < 0.001 {
                return majorColor
            }
        } else {
            // Other modes: every 5th line is major
            if abs(value.truncatingRemainder(dividingBy: spacing * 5.0)) < 0.001 {
                return majorColor
            }
        }
        return gridColor
    }

    private static func addXZPlane(
        _ vertices: inout [VertexIn],
        minX: Float, maxX: Float,
        minZ: Float, maxZ: Float,
        y: Float,
        spacing: Float,
        mode: GridMode
    ) {
        // Lines parallel to X axis (running along Z)
        var z = minZ
        while z <= maxZ {
            let color = getLineColor(value: z, spacing: spacing, mode: mode)
            vertices.append(VertexIn(position: SIMD3(minX, y, z), normal: SIMD3(0, 1, 0), color: color))
            vertices.append(VertexIn(position: SIMD3(maxX, y, z), normal: SIMD3(0, 1, 0), color: color))
            z += spacing
        }

        // Lines parallel to Z axis (running along X)
        var x = minX
        while x <= maxX {
            let color = getLineColor(value: x, spacing: spacing, mode: mode)
            vertices.append(VertexIn(position: SIMD3(x, y, minZ), normal: SIMD3(0, 1, 0), color: color))
            vertices.append(VertexIn(position: SIMD3(x, y, maxZ), normal: SIMD3(0, 1, 0), color: color))
            x += spacing
        }
    }

    private static func addXYPlane(
        _ vertices: inout [VertexIn],
        minX: Float, maxX: Float,
        minY: Float, maxY: Float,
        z: Float,
        spacing: Float,
        mode: GridMode
    ) {
        // Lines parallel to X axis (running along Y)
        var y = minY
        while y <= maxY {
            let color = getLineColor(value: y, spacing: spacing, mode: mode)
            vertices.append(VertexIn(position: SIMD3(minX, y, z), normal: SIMD3(0, 0, 1), color: color))
            vertices.append(VertexIn(position: SIMD3(maxX, y, z), normal: SIMD3(0, 0, 1), color: color))
            y += spacing
        }

        // Lines parallel to Y axis (running along X)
        var x = minX
        while x <= maxX {
            let color = getLineColor(value: x, spacing: spacing, mode: mode)
            vertices.append(VertexIn(position: SIMD3(x, minY, z), normal: SIMD3(0, 0, 1), color: color))
            vertices.append(VertexIn(position: SIMD3(x, maxY, z), normal: SIMD3(0, 0, 1), color: color))
            x += spacing
        }
    }

    private static func addYZPlane(
        _ vertices: inout [VertexIn],
        minY: Float, maxY: Float,
        minZ: Float, maxZ: Float,
        x: Float,
        spacing: Float,
        mode: GridMode
    ) {
        // Lines parallel to Y axis (running along Z)
        var z = minZ
        while z <= maxZ {
            let color = getLineColor(value: z, spacing: spacing, mode: mode)
            vertices.append(VertexIn(position: SIMD3(x, minY, z), normal: SIMD3(1, 0, 0), color: color))
            vertices.append(VertexIn(position: SIMD3(x, maxY, z), normal: SIMD3(1, 0, 0), color: color))
            z += spacing
        }

        // Lines parallel to Z axis (running along Y)
        var y = minY
        while y <= maxY {
            let color = getLineColor(value: y, spacing: spacing, mode: mode)
            vertices.append(VertexIn(position: SIMD3(x, y, minZ), normal: SIMD3(1, 0, 0), color: color))
            vertices.append(VertexIn(position: SIMD3(x, y, maxZ), normal: SIMD3(1, 0, 0), color: color))
            y += spacing
        }
    }

    private static func calculateGridSpacing(size: Float) -> Float {
        // Target approximately 10-20 grid lines
        let roughSpacing = size / 15.0

        // Find magnitude (power of 10)
        let magnitude = pow(10.0, floor(log10(roughSpacing)))

        // Try multiples: 1, 2, 5, 10
        let multiples: [Float] = [1.0, 2.0, 5.0, 10.0]
        var bestSpacing = magnitude

        for mult in multiples {
            let spacing = magnitude * mult
            if spacing >= roughSpacing {
                bestSpacing = spacing
                break
            }
        }

        return bestSpacing
    }

    private static func createDimensionLines(
        bboxMin: SIMD3<Float>,
        bboxMax: SIMD3<Float>,
        bottomY: Float
    ) -> [VertexIn] {
        var vertices: [VertexIn] = []
        let dimColor = SIMD4<Float>(255.0/255.0, 200.0/255.0, 100.0/255.0, 1.0) // Yellow
        let offset: Float = 5.0
        let markerSize: Float = 3.0

        // X dimension (width) - bottom front
        let x1Start = SIMD3(bboxMin.x, bottomY - offset, bboxMin.z - offset)
        let x1End = SIMD3(bboxMax.x, bottomY - offset, bboxMin.z - offset)
        vertices.append(VertexIn(position: x1Start, normal: SIMD3(0, 1, 0), color: dimColor))
        vertices.append(VertexIn(position: x1End, normal: SIMD3(0, 1, 0), color: dimColor))

        // X dimension markers
        vertices.append(VertexIn(position: SIMD3(bboxMin.x, bottomY - offset - markerSize, bboxMin.z - offset), normal: SIMD3(0, 1, 0), color: dimColor))
        vertices.append(VertexIn(position: SIMD3(bboxMin.x, bottomY - offset + markerSize, bboxMin.z - offset), normal: SIMD3(0, 1, 0), color: dimColor))
        vertices.append(VertexIn(position: SIMD3(bboxMax.x, bottomY - offset - markerSize, bboxMin.z - offset), normal: SIMD3(0, 1, 0), color: dimColor))
        vertices.append(VertexIn(position: SIMD3(bboxMax.x, bottomY - offset + markerSize, bboxMin.z - offset), normal: SIMD3(0, 1, 0), color: dimColor))

        // Z dimension (depth) - bottom left
        let z1Start = SIMD3(bboxMin.x - offset, bottomY - offset, bboxMin.z)
        let z1End = SIMD3(bboxMin.x - offset, bottomY - offset, bboxMax.z)
        vertices.append(VertexIn(position: z1Start, normal: SIMD3(0, 1, 0), color: dimColor))
        vertices.append(VertexIn(position: z1End, normal: SIMD3(0, 1, 0), color: dimColor))

        // Z dimension markers
        vertices.append(VertexIn(position: SIMD3(bboxMin.x - offset, bottomY - offset - markerSize, bboxMin.z), normal: SIMD3(0, 1, 0), color: dimColor))
        vertices.append(VertexIn(position: SIMD3(bboxMin.x - offset, bottomY - offset + markerSize, bboxMin.z), normal: SIMD3(0, 1, 0), color: dimColor))
        vertices.append(VertexIn(position: SIMD3(bboxMin.x - offset, bottomY - offset - markerSize, bboxMax.z), normal: SIMD3(0, 1, 0), color: dimColor))
        vertices.append(VertexIn(position: SIMD3(bboxMin.x - offset, bottomY - offset + markerSize, bboxMax.z), normal: SIMD3(0, 1, 0), color: dimColor))

        // Y dimension (height) - right front
        let y1Start = SIMD3(bboxMax.x + offset, bboxMin.y, bboxMin.z - offset)
        let y1End = SIMD3(bboxMax.x + offset, bboxMax.y, bboxMin.z - offset)
        vertices.append(VertexIn(position: y1Start, normal: SIMD3(0, 1, 0), color: dimColor))
        vertices.append(VertexIn(position: y1End, normal: SIMD3(0, 1, 0), color: dimColor))

        // Y dimension markers
        vertices.append(VertexIn(position: SIMD3(bboxMax.x + offset - markerSize, bboxMin.y, bboxMin.z - offset), normal: SIMD3(0, 1, 0), color: dimColor))
        vertices.append(VertexIn(position: SIMD3(bboxMax.x + offset + markerSize, bboxMin.y, bboxMin.z - offset), normal: SIMD3(0, 1, 0), color: dimColor))
        vertices.append(VertexIn(position: SIMD3(bboxMax.x + offset - markerSize, bboxMax.y, bboxMin.z - offset), normal: SIMD3(0, 1, 0), color: dimColor))
        vertices.append(VertexIn(position: SIMD3(bboxMax.x + offset + markerSize, bboxMax.y, bboxMin.z - offset), normal: SIMD3(0, 1, 0), color: dimColor))

        return vertices
    }

    /// Generate grid label data for text rendering
    func generateGridLabels() -> [(text: String, position: SIMD3<Float>, color: SIMD4<Float>, size: Float, orientation: TextOrientation)] {
        var labels: [(String, SIMD3<Float>, SIMD4<Float>, Float, TextOrientation)] = []
        let labelColor = SIMD4<Float>(200.0/255.0, 200.0/255.0, 200.0/255.0, 1.0) // White
        let labelSize: Float = 2.0

        // Determine label spacing based on mode
        let labelSpacing: Float = mode == .oneMM ? 10.0 : gridSpacing

        // X labels along bottom edge
        var x = ceil(bounds.minX / labelSpacing) * labelSpacing
        while x <= bounds.maxX {
            let text = String(format: "%.0f", x)
            let pos = SIMD3(x, bounds.bottomY, bounds.minZ - 2)
            labels.append((text, pos, labelColor, labelSize, .horizontal))
            x += labelSpacing
        }

        // Z labels along bottom edge (skip 0)
        var z = ceil(bounds.minZ / labelSpacing) * labelSpacing
        while z <= bounds.maxZ {
            if abs(z) > 0.001 {
                let text = String(format: "%.0f", z)
                let pos = SIMD3(bounds.minX - 2, bounds.bottomY, z)
                labels.append((text, pos, labelColor, labelSize, .horizontal))
            }
            z += labelSpacing
        }

        // Y labels (only in allSides and oneMM modes, skip 0)
        if mode == .allSides || mode == .oneMM {
            var y = ceil(bounds.minY / labelSpacing) * labelSpacing
            while y <= bounds.maxY {
                if abs(y) > 0.001 {
                    let text = String(format: "%.0f", y)
                    let pos = SIMD3(bounds.minX - 2, y, bounds.minZ - 2)
                    labels.append((text, pos, labelColor, labelSize, .verticalXY))
                }
                y += labelSpacing
            }
        }

        return labels
    }

    /// Generate dimension label data for text rendering
    func generateDimensionLabels() -> [(text: String, position: SIMD3<Float>, color: SIMD4<Float>, size: Float, orientation: TextOrientation)] {
        var labels: [(String, SIMD3<Float>, SIMD4<Float>, Float, TextOrientation)] = []
        let dimColor = SIMD4<Float>(255.0/255.0, 200.0/255.0, 100.0/255.0, 1.0) // Yellow
        let labelSize: Float = 2.5
        let offset: Float = 5.0

        let sizeX = bounds.bboxMaxX - bounds.bboxMinX
        let sizeY = bounds.bboxMaxY - bounds.bboxMinY
        let sizeZ = bounds.bboxMaxZ - bounds.bboxMinZ

        // X dimension label
        let xMid = (bounds.bboxMinX + bounds.bboxMaxX) / 2
        let xText = String(format: "X: %.1f mm", sizeX)
        labels.append((xText, SIMD3(xMid, bounds.bottomY - offset - 3, bounds.bboxMinZ - offset), dimColor, labelSize, .horizontal))

        // Z dimension label
        let zMid = (bounds.bboxMinZ + bounds.bboxMaxZ) / 2
        let zText = String(format: "Z: %.1f mm", sizeZ)
        labels.append((zText, SIMD3(bounds.bboxMinX - offset, bounds.bottomY - offset - 3, zMid), dimColor, labelSize, .horizontal))

        // Y dimension label
        let yMid = (bounds.bboxMinY + bounds.bboxMaxY) / 2
        let yText = String(format: "Y: %.1f mm", sizeY)
        labels.append((yText, SIMD3(bounds.bboxMaxX + offset + 3, yMid, bounds.bboxMinZ - offset), dimColor, labelSize, .verticalXY))

        return labels
    }
}
