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

    /// Grid bounds information for label rendering (Z-up coordinate system)
    struct GridBounds {
        let minX: Float
        let maxX: Float
        let minY: Float
        let maxY: Float
        let minZ: Float
        let maxZ: Float
        let bottomZ: Float  // Z coordinate of bottom grid plane
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
            minY: -size/2, maxY: size/2,
            minZ: 0, maxZ: size/2,
            bottomZ: 0,
            bboxMinX: -size/2, bboxMaxX: size/2,
            bboxMinY: -size/2, bboxMaxY: size/2,
            bboxMinZ: 0, bboxMaxZ: size/2
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
            bottomZ: Float(boundingBox.min.z),
            bboxMinX: Float(boundingBox.min.x),
            bboxMaxX: Float(boundingBox.max.x),
            bboxMinY: Float(boundingBox.min.y),
            bboxMaxY: Float(boundingBox.max.y),
            bboxMinZ: Float(boundingBox.min.z),
            bboxMaxZ: Float(boundingBox.max.z)
        )

        // Generate grid vertices based on mode (Z-up coordinate system)
        var vertices: [VertexIn] = []
        let bottomZ = Float(boundingBox.min.z)

        // Always draw bottom grid (XY plane at Z = bottomZ)
        GridData.addXYPlaneBottom(
            &vertices,
            minX: minX, maxX: maxX,
            minY: minY, maxY: maxY,
            z: bottomZ,
            spacing: spacing,
            mode: mode
        )

        // Add additional planes for allSides and oneMM modes
        if mode == .allSides || mode == .oneMM {
            // Back wall (XZ plane at max Y)
            GridData.addXZPlaneBack(
                &vertices,
                minX: minX, maxX: maxX,
                minZ: minZ, maxZ: maxZ,
                y: maxY,
                spacing: spacing,
                mode: mode
            )

            // Left wall (YZ plane at min X)
            GridData.addYZPlaneLeft(
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
            bottomZ: bottomZ
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

    /// Create simple grid on XY plane (Z-up coordinate system)
    private static func createSimpleGrid(size: Float, spacing: Float) -> [VertexIn] {
        var vertices: [VertexIn] = []
        let halfSize = size / 2.0
        let lineCount = Int(size / spacing)

        let majorColor = SIMD4<Float>(0.3, 0.3, 0.3, 1.0)
        let minorColor = SIMD4<Float>(0.2, 0.2, 0.2, 1.0)

        // Lines parallel to X axis (running along Y)
        for i in -lineCount...lineCount {
            let y = Float(i) * spacing
            let isMajorLine = i % 5 == 0
            let color = isMajorLine ? majorColor : minorColor

            vertices.append(VertexIn(position: SIMD3(-halfSize, y, 0), normal: SIMD3(0, 0, 1), color: color))
            vertices.append(VertexIn(position: SIMD3(halfSize, y, 0), normal: SIMD3(0, 0, 1), color: color))
        }

        // Lines parallel to Y axis (running along X)
        for i in -lineCount...lineCount {
            let x = Float(i) * spacing
            let isMajorLine = i % 5 == 0
            let color = isMajorLine ? majorColor : minorColor

            vertices.append(VertexIn(position: SIMD3(x, -halfSize, 0), normal: SIMD3(0, 0, 1), color: color))
            vertices.append(VertexIn(position: SIMD3(x, halfSize, 0), normal: SIMD3(0, 0, 1), color: color))
        }

        return vertices
    }

    private static func isSuperMajorLine(value: Float, spacing: Float, mode: GridMode) -> Bool {
        if mode == .oneMM {
            // In 1mm mode: every 10mm is super major
            return abs(value.truncatingRemainder(dividingBy: 10.0)) < 0.001
        } else {
            // Other modes: every 10th line is super major
            return abs(value.truncatingRemainder(dividingBy: spacing * 10.0)) < 0.001
        }
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
            // Other modes: every 10th line is super major, every 5th line is major
            if abs(value.truncatingRemainder(dividingBy: spacing * 10.0)) < 0.001 {
                return superMajorColor
            } else if abs(value.truncatingRemainder(dividingBy: spacing * 5.0)) < 0.001 {
                return majorColor
            }
        }
        return gridColor
    }

    /// Bottom grid: XY plane at given Z (Z-up coordinate system)
    private static func addXYPlaneBottom(
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

    /// Back wall: XZ plane at given Y (Z-up coordinate system)
    private static func addXZPlaneBack(
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
            vertices.append(VertexIn(position: SIMD3(minX, y, z), normal: SIMD3(0, -1, 0), color: color))
            vertices.append(VertexIn(position: SIMD3(maxX, y, z), normal: SIMD3(0, -1, 0), color: color))
            z += spacing
        }

        // Lines parallel to Z axis (running along X)
        var x = minX
        while x <= maxX {
            let color = getLineColor(value: x, spacing: spacing, mode: mode)
            vertices.append(VertexIn(position: SIMD3(x, y, minZ), normal: SIMD3(0, -1, 0), color: color))
            vertices.append(VertexIn(position: SIMD3(x, y, maxZ), normal: SIMD3(0, -1, 0), color: color))
            x += spacing
        }
    }

    /// Left wall: YZ plane at given X (Z-up coordinate system)
    private static func addYZPlaneLeft(
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

    /// Create dimension marker lines (Z-up coordinate system)
    private static func createDimensionLines(
        bboxMin: SIMD3<Float>,
        bboxMax: SIMD3<Float>,
        bottomZ: Float
    ) -> [VertexIn] {
        var vertices: [VertexIn] = []
        let dimColor = SIMD4<Float>(255.0/255.0, 200.0/255.0, 100.0/255.0, 1.0) // Orange
        let markerSize: Float = 3.0

        // X axis indicator - simple marker at max X (front edge)
        let xPos = SIMD3(bboxMax.x, bboxMin.y - 2, bottomZ)
        vertices.append(VertexIn(position: SIMD3(xPos.x, xPos.y, xPos.z - markerSize), normal: SIMD3(0, 0, 1), color: dimColor))
        vertices.append(VertexIn(position: SIMD3(xPos.x, xPos.y, xPos.z + markerSize), normal: SIMD3(0, 0, 1), color: dimColor))

        // Y axis indicator - simple marker at max Y (left edge)
        let yPos = SIMD3(bboxMin.x - 2, bboxMax.y, bottomZ)
        vertices.append(VertexIn(position: SIMD3(yPos.x, yPos.y, yPos.z - markerSize), normal: SIMD3(0, 0, 1), color: dimColor))
        vertices.append(VertexIn(position: SIMD3(yPos.x, yPos.y, yPos.z + markerSize), normal: SIMD3(0, 0, 1), color: dimColor))

        // Z axis indicator - simple marker at max Z (vertical)
        let zPos = SIMD3(bboxMin.x - 2, bboxMax.y + 2, bboxMax.z)
        vertices.append(VertexIn(position: SIMD3(zPos.x - markerSize, zPos.y, zPos.z), normal: SIMD3(0, -1, 0), color: dimColor))
        vertices.append(VertexIn(position: SIMD3(zPos.x + markerSize, zPos.y, zPos.z), normal: SIMD3(0, -1, 0), color: dimColor))

        return vertices
    }

    /// Generate grid label data for text rendering (Z-up coordinate system)
    func generateGridLabels() -> [(text: String, position: SIMD3<Float>, color: SIMD4<Float>, size: Float, orientation: TextOrientation)] {
        var labels: [(String, SIMD3<Float>, SIMD4<Float>, Float, TextOrientation)] = []
        let labelColor = SIMD4<Float>(200.0/255.0, 200.0/255.0, 200.0/255.0, 1.0) // White
        let labelSize: Float = 2.0

        // Always show labels at fixed 10-unit intervals
        let labelSpacing: Float = 10.0

        // X labels along front edge (at minY)
        var x = ceil(bounds.minX / labelSpacing) * labelSpacing
        while x <= bounds.maxX {
            let text = String(format: "%.0f", x)
            let pos = SIMD3(x, bounds.minY - 2, bounds.bottomZ)
            labels.append((text, pos, labelColor, labelSize, .horizontal))
            x += labelSpacing
        }

        // Y labels along left edge (skip 0)
        var y = ceil(bounds.minY / labelSpacing) * labelSpacing
        while y <= bounds.maxY {
            if abs(y) > 0.001 {
                let text = String(format: "%.0f", y)
                let pos = SIMD3(bounds.minX - 2, y, bounds.bottomZ)
                labels.append((text, pos, labelColor, labelSize, .horizontal))
            }
            y += labelSpacing
        }

        // Z labels (vertical, only in allSides and oneMM modes, skip 0)
        if mode == .allSides || mode == .oneMM {
            var z = ceil(bounds.minZ / labelSpacing) * labelSpacing
            while z <= bounds.maxZ {
                if abs(z) > 0.001 {
                    let text = String(format: "%.0f", z)
                    let pos = SIMD3(bounds.minX - 2, bounds.maxY + 2, z)
                    labels.append((text, pos, labelColor, labelSize, .verticalYZ))
                }
                z += labelSpacing
            }
        }

        return labels
    }

    /// Generate dimension label data for text rendering (Z-up coordinate system)
    func generateDimensionLabels() -> [(text: String, position: SIMD3<Float>, color: SIMD4<Float>, size: Float, orientation: TextOrientation)] {
        var labels: [(String, SIMD3<Float>, SIMD4<Float>, Float, TextOrientation)] = []
        let dimColor = SIMD4<Float>(255.0/255.0, 200.0/255.0, 100.0/255.0, 1.0) // Orange
        let labelSize: Float = 1.75

        let sizeX = bounds.bboxMaxX - bounds.bboxMinX
        let sizeY = bounds.bboxMaxY - bounds.bboxMinY
        let sizeZ = bounds.bboxMaxZ - bounds.bboxMinZ

        // X dimension label - positioned near the X marker (front edge)
        let xText = String(format: "X: %.1f mm", sizeX)
        labels.append((xText, SIMD3(bounds.bboxMaxX, bounds.bboxMinY - 2, bounds.bottomZ), dimColor, labelSize, .horizontal))

        // Y dimension label - positioned near the Y marker (left edge)
        let yText = String(format: "Y: %.1f mm", sizeY)
        labels.append((yText, SIMD3(bounds.bboxMinX - 2, bounds.bboxMaxY, bounds.bottomZ), dimColor, labelSize, .horizontal))

        // Z dimension label - positioned near the Z marker (vertical)
        let zText = String(format: "Z: %.1f mm", sizeZ)
        labels.append((zText, SIMD3(bounds.bboxMinX - 2, bounds.bboxMaxY + 2, bounds.bboxMaxZ + labelSize * 0.6), dimColor, labelSize, .verticalYZ))

        return labels
    }
}
