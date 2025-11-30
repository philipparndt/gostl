import Metal
import simd
import CoreText
import CoreGraphics
import AppKit

/// Represents one face of the orientation cube
enum CubeFace: Int, CaseIterable {
    case top = 0
    case bottom = 1
    case front = 2
    case back = 3
    case left = 4
    case right = 5

    var label: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .front: return "Front"
        case .back: return "Back"
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    var keyboardShortcut: String {
        switch self {
        case .front: return "1"
        case .back: return "2"
        case .left: return "3"
        case .right: return "4"
        case .top: return "5"
        case .bottom: return "6"
        }
    }

    var baseColor: SIMD4<Float> {
        switch self {
        case .top:    return SIMD4(0.3, 0.3, 0.35, 1.0)  // Slightly lighter gray
        case .bottom: return SIMD4(0.2, 0.2, 0.25, 1.0)  // Darker gray
        case .front:  return SIMD4(0.25, 0.25, 0.30, 1.0)
        case .back:   return SIMD4(0.25, 0.25, 0.30, 1.0)
        case .left:   return SIMD4(0.25, 0.25, 0.30, 1.0)
        case .right:  return SIMD4(0.25, 0.25, 0.30, 1.0)
        }
    }

    var hoverColor: SIMD4<Float> {
        // Brighter version of base color
        let base = baseColor
        return SIMD4(
            min(base.x * 1.5, 1.0),
            min(base.y * 1.5, 1.0),
            min(base.z * 1.5, 1.0),
            base.w
        )
    }

    var cameraPreset: CameraPreset {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .front: return .front
        case .back: return .back
        case .left: return .left
        case .right: return .right
        }
    }

    /// Get the normal vector for this face
    var normal: SIMD3<Float> {
        switch self {
        case .top:    return SIMD3(0, 1, 0)
        case .bottom: return SIMD3(0, -1, 0)
        case .front:  return SIMD3(0, 0, 1)
        case .back:   return SIMD3(0, 0, -1)
        case .left:   return SIMD3(-1, 0, 0)
        case .right:  return SIMD3(1, 0, 0)
        }
    }
}

/// Axis enumeration for the orientation cube
enum Axis: Int, CaseIterable {
    case x = 0
    case y = 1
    case z = 2

    var label: String {
        switch self {
        case .x: return "X"
        case .y: return "Y"
        case .z: return "Z"
        }
    }

    var color: SIMD4<Float> {
        switch self {
        case .x: return AxisColors.x
        case .y: return AxisColors.y
        case .z: return AxisColors.z
        }
    }
}

/// GPU data for rendering the orientation cube
final class OrientationCubeData {
    let device: MTLDevice
    let vertexBuffer: MTLBuffer
    let vertexCount: Int

    // Text rendering data (face labels)
    let textVertexBuffer: MTLBuffer?
    let textTextures: [(texture: MTLTexture, vertexOffset: Int)]

    // Keyboard shortcut rendering data
    let shortcutBackgroundBuffer: MTLBuffer?
    let shortcutBackgroundCount: Int
    let shortcutBackgroundTexture: MTLTexture?
    let shortcutTextVertexBuffer: MTLBuffer?
    let shortcutTextTextures: [(texture: MTLTexture, vertexOffset: Int)]

    // Axis lines rendering data (using cylinders for thickness)
    let axisVertexBuffer: MTLBuffer?
    let axisIndexBuffer: MTLBuffer?
    let axisVertexCount: Int
    let axisIndexCount: Int

    // Axis labels rendering data (camera-facing billboards)
    struct AxisLabelInfo {
        let axis: Axis
        let position: SIMD3<Float>
        let texture: MTLTexture
        let size: Float
    }
    let axisLabels: [AxisLabelInfo]

    // Face information for hit testing
    struct FaceInfo {
        let face: CubeFace
        let center: SIMD3<Float>
        let normal: SIMD3<Float>
    }
    let faces: [FaceInfo]

    init(device: MTLDevice, size: Float = 1.0) throws {
        self.device = device

        // Generate cube geometry (6 faces, 2 triangles per face, 3 vertices per triangle)
        let vertices = Self.generateCubeVertices(size: size)
        self.vertexCount = vertices.count

        // Create vertex buffer
        guard let buffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<VertexIn>.stride,
            options: .storageModeShared
        ) else {
            throw MetalError.pipelineCreationFailed
        }
        self.vertexBuffer = buffer

        // Generate face information for hit testing
        self.faces = CubeFace.allCases.map { face in
            FaceInfo(
                face: face,
                center: face.normal * size * 0.5,
                normal: face.normal
            )
        }

        // Generate properly oriented text quads
        let textData = try Self.generateOrientedTextQuads(device: device, size: size)
        self.textVertexBuffer = textData.vertexBuffer
        self.textTextures = textData.textureData

        // Generate axis lines using cylinders for thickness
        let axisData = Self.generateAxisCylinders(device: device, size: size)
        self.axisVertexBuffer = axisData.vertexBuffer
        self.axisIndexBuffer = axisData.indexBuffer
        self.axisVertexCount = axisData.vertexCount
        self.axisIndexCount = axisData.indexCount

        // Generate axis label info (textures and positions)
        self.axisLabels = try Self.generateAxisLabelInfo(device: device, size: size)

        // Generate keyboard shortcut backgrounds and text
        let shortcutData = try Self.generateKeyboardShortcuts(device: device, size: size)
        self.shortcutBackgroundBuffer = shortcutData.backgroundBuffer
        self.shortcutBackgroundCount = shortcutData.backgroundCount
        self.shortcutBackgroundTexture = shortcutData.backgroundTexture
        self.shortcutTextVertexBuffer = shortcutData.textVertexBuffer
        self.shortcutTextTextures = shortcutData.textureData
    }

    /// Generate cube vertices with per-face colors
    private static func generateCubeVertices(size: Float) -> [VertexIn] {
        var vertices: [VertexIn] = []
        let s = size * 0.5  // Half size for centering

        // Helper to add a quad (2 triangles)
        func addQuad(
            v0: SIMD3<Float>, v1: SIMD3<Float>,
            v2: SIMD3<Float>, v3: SIMD3<Float>,
            normal: SIMD3<Float>, color: SIMD4<Float>
        ) {
            // First triangle (v0, v1, v2)
            vertices.append(VertexIn(position: v0, normal: normal, color: color))
            vertices.append(VertexIn(position: v1, normal: normal, color: color))
            vertices.append(VertexIn(position: v2, normal: normal, color: color))
            // Second triangle (v0, v2, v3)
            vertices.append(VertexIn(position: v0, normal: normal, color: color))
            vertices.append(VertexIn(position: v2, normal: normal, color: color))
            vertices.append(VertexIn(position: v3, normal: normal, color: color))
        }

        // Top face (Y+)
        addQuad(
            v0: SIMD3(-s, s, -s), v1: SIMD3(s, s, -s),
            v2: SIMD3(s, s, s), v3: SIMD3(-s, s, s),
            normal: CubeFace.top.normal,
            color: CubeFace.top.baseColor
        )

        // Bottom face (Y-)
        addQuad(
            v0: SIMD3(-s, -s, s), v1: SIMD3(s, -s, s),
            v2: SIMD3(s, -s, -s), v3: SIMD3(-s, -s, -s),
            normal: CubeFace.bottom.normal,
            color: CubeFace.bottom.baseColor
        )

        // Front face (Z+)
        addQuad(
            v0: SIMD3(-s, -s, s), v1: SIMD3(s, -s, s),
            v2: SIMD3(s, s, s), v3: SIMD3(-s, s, s),
            normal: CubeFace.front.normal,
            color: CubeFace.front.baseColor
        )

        // Back face (Z-)
        addQuad(
            v0: SIMD3(s, -s, -s), v1: SIMD3(-s, -s, -s),
            v2: SIMD3(-s, s, -s), v3: SIMD3(s, s, -s),
            normal: CubeFace.back.normal,
            color: CubeFace.back.baseColor
        )

        // Left face (X-)
        addQuad(
            v0: SIMD3(-s, -s, -s), v1: SIMD3(-s, -s, s),
            v2: SIMD3(-s, s, s), v3: SIMD3(-s, s, -s),
            normal: CubeFace.left.normal,
            color: CubeFace.left.baseColor
        )

        // Right face (X+)
        addQuad(
            v0: SIMD3(s, -s, s), v1: SIMD3(s, -s, -s),
            v2: SIMD3(s, s, -s), v3: SIMD3(s, s, s),
            normal: CubeFace.right.normal,
            color: CubeFace.right.baseColor
        )

        return vertices
    }

    /// Generate properly oriented text labels for each cube face
    private static func generateOrientedTextQuads(device: MTLDevice, size: Float) throws -> (vertexBuffer: MTLBuffer, textureData: [(texture: MTLTexture, vertexOffset: Int)]) {
        var allVertices: [VertexIn] = []
        var textureData: [(texture: MTLTexture, vertexOffset: Int)] = []

        let textSize = size * 0.6  // Text quad size (1.5x larger: 0.4 * 1.5 = 0.6)

        for face in CubeFace.allCases {
            // Create text texture for this face
            guard let texture = Self.createFaceTextTexture(device: device, text: face.label, faceColor: face.baseColor) else {
                continue
            }

            // Record vertex offset for this face
            let vertexOffset = allVertices.count
            textureData.append((texture: texture, vertexOffset: vertexOffset))

            // Create properly oriented quad for this face
            let faceQuad = Self.createOrientedTextQuad(
                face: face,
                size: textSize,
                cubeSize: size
            )
            allVertices.append(contentsOf: faceQuad)
        }

        // Create vertex buffer
        guard let buffer = device.makeBuffer(
            bytes: allVertices,
            length: allVertices.count * MemoryLayout<VertexIn>.stride,
            options: .storageModeShared
        ) else {
            throw MetalError.bufferCreationFailed
        }

        return (vertexBuffer: buffer, textureData: textureData)
    }

    /// Create a properly oriented text quad for a specific face
    private static func createOrientedTextQuad(face: CubeFace, size: Float, cubeSize: Float) -> [VertexIn] {
        let offset = cubeSize * 0.51  // Slightly in front of face
        let position = face.normal * offset
        let halfSize = size / 2.0

        // Define right and up vectors for each face to ensure text is upright and readable
        let (right, up): (SIMD3<Float>, SIMD3<Float>) = {
            switch face {
            case .top:
                // Was correct before - reverting
                return (SIMD3(1, 0, 0), SIMD3(0, 0, 1))
            case .bottom:
                // Rotated 180deg - flip only up vector (not right, to avoid mirroring)
                return (SIMD3(1, 0, 0), SIMD3(0, 0, -1))
            case .front:
                // Vertically mirrored - flip up vector
                return (SIMD3(1, 0, 0), SIMD3(0, -1, 0))
            case .back:
                // Rotated 180deg - flip both vectors
                return (SIMD3(-1, 0, 0), SIMD3(0, -1, 0))
            case .left:
                // Horizontally mirrored - flip right vector
                return (SIMD3(0, 0, 1), SIMD3(0, -1, 0))
            case .right:
                // Vertically mirrored - flip up vector
                return (SIMD3(0, 0, -1), SIMD3(0, -1, 0))
            }
        }()

        // Create quad vertices
        let v0 = position - right * halfSize - up * halfSize
        let v1 = position + right * halfSize - up * halfSize
        let v2 = position + right * halfSize + up * halfSize
        let v3 = position - right * halfSize + up * halfSize

        let color = SIMD4<Float>(1, 1, 1, 1)
        let normal = face.normal

        return [
            // Triangle 1
            VertexIn(position: v0, normal: normal, color: color, texCoord: SIMD2(0, 1)),
            VertexIn(position: v1, normal: normal, color: color, texCoord: SIMD2(1, 1)),
            VertexIn(position: v2, normal: normal, color: color, texCoord: SIMD2(1, 0)),
            // Triangle 2
            VertexIn(position: v0, normal: normal, color: color, texCoord: SIMD2(0, 1)),
            VertexIn(position: v2, normal: normal, color: color, texCoord: SIMD2(1, 0)),
            VertexIn(position: v3, normal: normal, color: color, texCoord: SIMD2(0, 0))
        ]
    }

    /// Create text texture for a cube face
    private static func createFaceTextTexture(device: MTLDevice, text: String, faceColor: SIMD4<Float>) -> MTLTexture? {
        // Use fixed texture size for all labels to ensure consistent text size
        let textureSize = 256
        let fontSize: CGFloat = 80  // Increased from 64

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: textureSize,
            height: textureSize,
            bitsPerComponent: 8,
            bytesPerRow: textureSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Clear background (fully transparent)
        context.clear(CGRect(x: 0, y: 0, width: textureSize, height: textureSize))

        // Draw text centered
        context.textMatrix = .identity
        context.translateBy(x: 0, y: CGFloat(textureSize))
        context.scaleBy(x: 1.0, y: -1.0)

        let line = CTLineCreateWithAttributedString(attributedString)
        // Get text bounds for better vertical centering
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        // Center the text horizontally and vertically in the fixed-size texture
        let xOffset = (CGFloat(textureSize) - textSize.width) / 2.0
        // Adjust vertical position to truly center the text, then move up slightly
        let centerOffset = (CGFloat(textureSize) - bounds.height) / 2.0 - bounds.origin.y
        let additionalUpwardOffset: CGFloat = 10  // Move up by additional pixels (reduced from 20)
        let yOffset = centerOffset + additionalUpwardOffset
        context.textPosition = CGPoint(x: xOffset, y: yOffset)
        CTLineDraw(line, context)

        guard let data = context.data else {
            return nil
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: textureSize,
            height: textureSize,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, textureSize, textureSize),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: textureSize * 4
        )

        return texture
    }

    /// Generate axis lines as cylinders for thickness (non-instanced)
    private static func generateAxisCylinders(device: MTLDevice, size: Float) -> (
        vertexBuffer: MTLBuffer?,
        indexBuffer: MTLBuffer?,
        vertexCount: Int,
        indexCount: Int
    ) {
        let s = size * 0.5  // Half size
        let thickness: Float = 0.02  // 50% reduction
        let segments = 8

        // Define axis endpoints - X and Y at front, Z going back
        let origin = SIMD3<Float>(-s, -s, s)  // Front-left-bottom corner
        struct AxisLine {
            let start: SIMD3<Float>
            let end: SIMD3<Float>
            let color: SIMD4<Float>
        }

        let axisLines = [
            // X axis: horizontal line at bottom of front face (Red)
            AxisLine(start: origin, end: SIMD3(s, -s, s), color: Axis.x.color),
            // Y axis: vertical line at front-left corner (Green)
            AxisLine(start: origin, end: SIMD3(-s, s, s), color: Axis.y.color),
            // Z axis: line from front to back at bottom-left (Blue)
            AxisLine(start: origin, end: SIMD3(-s, -s, -s), color: Axis.z.color)
        ]

        var allVertices: [VertexIn] = []
        var allIndices: [UInt16] = []

        // Generate cylinder geometry for each axis
        for line in axisLines {
            let direction = line.end - line.start
            let length = simd_length(direction)
            let axis = direction / length

            // Create rotation to align Y-axis with direction
            let arbitrary = abs(axis.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            let right = simd_normalize(simd_cross(arbitrary, axis))
            let forward = simd_cross(axis, right)

            let baseIndex = UInt16(allVertices.count)

            // Generate cylinder vertices
            for i in 0...segments {
                let theta = Float(i) * 2.0 * .pi / Float(segments)
                let x = thickness * cos(theta)
                let z = thickness * sin(theta)

                // Local normal for cylinder
                let localNormal = simd_normalize(SIMD3<Float>(x, 0, z))
                // Transform normal to world space
                let worldNormal = simd_normalize(right * localNormal.x + forward * localNormal.z)

                // Transform vertex position to world space
                let localBottom = SIMD3<Float>(x, 0, z)
                let localTop = SIMD3<Float>(x, length, z)
                let worldBottom = line.start + right * localBottom.x + axis * localBottom.y + forward * localBottom.z
                let worldTop = line.start + right * localTop.x + axis * localTop.y + forward * localTop.z

                // Bottom vertex
                allVertices.append(VertexIn(position: worldBottom, normal: worldNormal, color: line.color))
                // Top vertex
                allVertices.append(VertexIn(position: worldTop, normal: worldNormal, color: line.color))
            }

            // Generate indices for this cylinder
            for i in 0..<segments {
                let base = baseIndex + UInt16(i * 2)
                allIndices.append(base)
                allIndices.append(base + 2)
                allIndices.append(base + 1)
                allIndices.append(base + 1)
                allIndices.append(base + 2)
                allIndices.append(base + 3)
            }
        }

        // Create vertex buffer
        guard let vertexBuffer = device.makeBuffer(
            bytes: allVertices,
            length: allVertices.count * MemoryLayout<VertexIn>.stride,
            options: []
        ) else {
            return (nil, nil, 0, 0)
        }

        // Create index buffer
        guard let indexBuffer = device.makeBuffer(
            bytes: allIndices,
            length: allIndices.count * MemoryLayout<UInt16>.stride,
            options: []
        ) else {
            return (nil, nil, 0, 0)
        }

        return (vertexBuffer, indexBuffer, allVertices.count, allIndices.count)
    }

    /// Generate axis label information (textures and positions)
    private static func generateAxisLabelInfo(device: MTLDevice, size: Float) throws -> [AxisLabelInfo] {
        let s = size * 0.5
        let labelSize = size * 0.2
        let labelOffset = size * 0.18  // Increased distance from axis end to avoid intersection

        var labels: [AxisLabelInfo] = []

        for axis in Axis.allCases {
            // Create text texture for this axis
            guard let texture = Self.createAxisLabelTexture(device: device, text: axis.label, color: axis.color) else {
                continue
            }

            // Position label at end of axis line (axes meet at front-left-bottom corner)
            let position: SIMD3<Float> = {
                switch axis {
                case .x:
                    // At right end of X axis (front-bottom edge)
                    return SIMD3(s + labelOffset, -s, s)
                case .y:
                    // At top end of Y axis (front-left edge)
                    return SIMD3(-s, s + labelOffset, s)
                case .z:
                    // At back end of Z axis (back-left-bottom corner)
                    return SIMD3(-s, -s, -s - labelOffset)
                }
            }()

            labels.append(AxisLabelInfo(
                axis: axis,
                position: position,
                texture: texture,
                size: labelSize
            ))
        }

        return labels
    }

    /// Create text texture for an axis label
    private static func createAxisLabelTexture(device: MTLDevice, text: String, color: SIMD4<Float>) -> MTLTexture? {
        let textureSize = 128
        let fontSize: CGFloat = 90  // Bigger font

        let nsColor = NSColor(
            red: CGFloat(color.x),
            green: CGFloat(color.y),
            blue: CGFloat(color.z),
            alpha: CGFloat(color.w)
        )

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: nsColor
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: textureSize,
            height: textureSize,
            bitsPerComponent: 8,
            bytesPerRow: textureSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: textureSize, height: textureSize))
        context.textMatrix = .identity
        context.translateBy(x: 0, y: CGFloat(textureSize))
        context.scaleBy(x: 1.0, y: -1.0)

        let line = CTLineCreateWithAttributedString(attributedString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let xOffset = (CGFloat(textureSize) - textSize.width) / 2.0
        let centerOffset = (CGFloat(textureSize) - bounds.height) / 2.0 - bounds.origin.y
        let yOffset = centerOffset

        context.textPosition = CGPoint(x: xOffset, y: yOffset)
        CTLineDraw(line, context)

        guard let data = context.data else {
            return nil
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: textureSize,
            height: textureSize,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, textureSize, textureSize),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: textureSize * 4
        )

        return texture
    }

    /// Generate keyboard shortcut backgrounds and text for each face
    private static func generateKeyboardShortcuts(device: MTLDevice, size: Float) throws -> (
        backgroundBuffer: MTLBuffer?,
        backgroundCount: Int,
        backgroundTexture: MTLTexture?,
        textVertexBuffer: MTLBuffer?,
        textureData: [(texture: MTLTexture, vertexOffset: Int)]
    ) {
        var backgroundVertices: [VertexIn] = []
        var textVertices: [VertexIn] = []
        var textureData: [(texture: MTLTexture, vertexOffset: Int)] = []

        let shortcutSize = size * 0.25  // Size of the shortcut badge
        let offset = size * 0.30  // Position from center (lower = higher on face)
        let backgroundPadding: Float = 0.02  // Padding around text
        let depthOffset: Float = 0.001  // Tiny offset between background and text

        for face in CubeFace.allCases {
            // Create text texture for keyboard shortcut
            guard let texture = Self.createShortcutTexture(device: device, text: face.keyboardShortcut) else {
                continue
            }

            let vertexOffset = textVertices.count
            textureData.append((texture: texture, vertexOffset: vertexOffset))

            // Calculate position at bottom center of face
            // Offset to position shortcuts in front of face labels (which are at 0.51)
            let (position, right, up): (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) = {
                let faceOffset = offset
                let cubeOffset: Float = 0.015  // Enough to be in front of face labels at 0.51
                switch face {
                case .top:
                    // Top face - bottom center (fix mirrored + rotated 180°)
                    return (
                        SIMD3(0, size * 0.5 + cubeOffset, faceOffset),
                        SIMD3(1, 0, 0),      // Keep right same
                        SIMD3(0, 0, 1)       // Flip up for combined fix
                    )
                case .bottom:
                    // Bottom face - bottom center (fix mirrored + rotated 180°)
                    return (
                        SIMD3(0, -size * 0.5 - cubeOffset, -faceOffset),
                        SIMD3(1, 0, 0),      // Keep right same
                        SIMD3(0, 0, -1)      // Flip up for combined fix
                    )
                case .front:
                    // Front face - bottom center (fix mirroring)
                    return (
                        SIMD3(0, -faceOffset, size * 0.5 + cubeOffset),
                        SIMD3(1, 0, 0),   // Flipped right vector to fix mirror
                        SIMD3(0, -1, 0)
                    )
                case .back:
                    // Back face - bottom center (fix mirroring)
                    return (
                        SIMD3(0, -faceOffset, -size * 0.5 - cubeOffset),
                        SIMD3(-1, 0, 0),  // Flipped right vector to fix mirror
                        SIMD3(0, -1, 0)
                    )
                case .left:
                    // Left face - bottom center (already correct)
                    return (
                        SIMD3(-size * 0.5 - cubeOffset, -faceOffset, 0),
                        SIMD3(0, 0, 1),
                        SIMD3(0, 1, 0)
                    )
                case .right:
                    // Right face - bottom center (fix 180° rotation)
                    return (
                        SIMD3(size * 0.5 + cubeOffset, -faceOffset, 0),
                        SIMD3(0, 0, -1),  // Flipped for 180° rotation
                        SIMD3(0, -1, 0)   // Flipped for 180° rotation
                    )
                }
            }()

            let whiteColor = SIMD4<Float>(1, 1, 1, 1)

            // Create background quad - portrait orientation (taller than wide) for single digit shortcuts
            let bgHalfWidth = shortcutSize / 3.0 + backgroundPadding  // Narrower
            let bgHalfHeight = shortcutSize / 2.2 + backgroundPadding  // Slightly reduced height
            let bgV0 = position - right * bgHalfWidth - up * bgHalfHeight
            let bgV1 = position + right * bgHalfWidth - up * bgHalfHeight
            let bgV2 = position + right * bgHalfWidth + up * bgHalfHeight
            let bgV3 = position - right * bgHalfWidth + up * bgHalfHeight
            backgroundVertices.append(contentsOf: [
                VertexIn(position: bgV0, normal: face.normal, color: whiteColor, texCoord: SIMD2(0, 1)),  // bottom-left
                VertexIn(position: bgV1, normal: face.normal, color: whiteColor, texCoord: SIMD2(1, 1)),  // bottom-right
                VertexIn(position: bgV2, normal: face.normal, color: whiteColor, texCoord: SIMD2(1, 0)),  // top-right
                VertexIn(position: bgV0, normal: face.normal, color: whiteColor, texCoord: SIMD2(0, 1)),  // bottom-left
                VertexIn(position: bgV2, normal: face.normal, color: whiteColor, texCoord: SIMD2(1, 0)),  // top-right
                VertexIn(position: bgV3, normal: face.normal, color: whiteColor, texCoord: SIMD2(0, 0))   // top-left
            ])

            // Create text quad - same portrait orientation as background
            let halfWidth = shortcutSize / 3.0  // Narrower
            let halfHeight = shortcutSize / 2.2  // Slightly reduced height
            let v0 = position - right * halfWidth - up * halfHeight + face.normal * depthOffset
            let v1 = position + right * halfWidth - up * halfHeight + face.normal * depthOffset
            let v2 = position + right * halfWidth + up * halfHeight + face.normal * depthOffset
            let v3 = position - right * halfWidth + up * halfHeight + face.normal * depthOffset

            textVertices.append(contentsOf: [
                VertexIn(position: v0, normal: face.normal, color: whiteColor, texCoord: SIMD2(0, 1)),  // bottom-left
                VertexIn(position: v1, normal: face.normal, color: whiteColor, texCoord: SIMD2(1, 1)),  // bottom-right
                VertexIn(position: v2, normal: face.normal, color: whiteColor, texCoord: SIMD2(1, 0)),  // top-right
                VertexIn(position: v0, normal: face.normal, color: whiteColor, texCoord: SIMD2(0, 1)),  // bottom-left
                VertexIn(position: v2, normal: face.normal, color: whiteColor, texCoord: SIMD2(1, 0)),  // top-right
                VertexIn(position: v3, normal: face.normal, color: whiteColor, texCoord: SIMD2(0, 0))   // top-left
            ])
        }

        // Create background buffer
        let backgroundBuffer: MTLBuffer?
        if !backgroundVertices.isEmpty {
            backgroundBuffer = device.makeBuffer(
                bytes: backgroundVertices,
                length: backgroundVertices.count * MemoryLayout<VertexIn>.stride,
                options: .storageModeShared
            )
        } else {
            backgroundBuffer = nil
        }

        // Create text vertex buffer
        let textBuffer: MTLBuffer?
        if !textVertices.isEmpty {
            textBuffer = device.makeBuffer(
                bytes: textVertices,
                length: textVertices.count * MemoryLayout<VertexIn>.stride,
                options: .storageModeShared
            )
        } else {
            textBuffer = nil
        }

        // Create background texture (shared across all shortcuts)
        let backgroundTexture = Self.createRoundedBackgroundTexture(device: device)

        return (backgroundBuffer, backgroundVertices.count, backgroundTexture, textBuffer, textureData)
    }

    /// Create text texture for a keyboard shortcut (single digit)
    private static func createShortcutTexture(device: MTLDevice, text: String) -> MTLTexture? {
        let textureSize = 64
        let fontSize: CGFloat = 32

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: textureSize,
            height: textureSize,
            bitsPerComponent: 8,
            bytesPerRow: textureSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: textureSize, height: textureSize))
        context.textMatrix = .identity
        context.translateBy(x: 0, y: CGFloat(textureSize))
        context.scaleBy(x: 1.0, y: -1.0)

        let line = CTLineCreateWithAttributedString(attributedString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let xOffset = (CGFloat(textureSize) - textSize.width) / 2.0
        let centerOffset = (CGFloat(textureSize) - bounds.height) / 2.0 - bounds.origin.y
        let yOffset = centerOffset

        context.textPosition = CGPoint(x: xOffset, y: yOffset)
        CTLineDraw(line, context)

        guard let data = context.data else {
            return nil
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: textureSize,
            height: textureSize,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, textureSize, textureSize),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: textureSize * 4
        )

        return texture
    }

    /// Create rounded rectangle background texture (portrait orientation for single digits)
    private static func createRoundedBackgroundTexture(device: MTLDevice) -> MTLTexture? {
        let textureWidth = 48   // Narrower
        let textureHeight = 64  // Taller (portrait, ratio ~0.75)
        let cornerRadius: CGFloat = 10  // Increased for more rounded corners
        let borderWidth: CGFloat = 4    // Border thickness (doubled)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: textureWidth,
            height: textureHeight,
            bitsPerComponent: 8,
            bytesPerRow: textureWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Clear the context
        context.clear(CGRect(x: 0, y: 0, width: textureWidth, height: textureHeight))

        // Draw rounded rectangle with inset to accommodate border
        let inset = borderWidth / 2
        let rect = CGRect(x: inset, y: inset, width: CGFloat(textureWidth) - borderWidth, height: CGFloat(textureHeight) - borderWidth)
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        // Fill with background color - white with low opacity (matching KeyHint UI)
        context.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.2)
        context.addPath(path)
        context.fillPath()

        // Draw border/stroke - white with medium opacity (matching KeyHint UI)
        context.addPath(path)
        context.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.4)
        context.setLineWidth(borderWidth)
        context.strokePath()

        guard let data = context.data else {
            return nil
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: textureWidth,
            height: textureHeight,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, textureWidth, textureHeight),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: textureWidth * 4
        )

        return texture
    }

    /// Find which face (if any) is hit by a ray in cube-local space
    /// Only returns faces that are visible (front-facing) from the ray origin
    func hitTest(ray: Ray) -> CubeFace? {
        var closestFace: CubeFace?
        var closestDistance = Float.infinity

        for faceInfo in faces {
            // Check if face is front-facing (visible from ray origin)
            // The face normal points outward, ray direction points into the cube
            // If dot product is negative, face is front-facing
            let viewDot = simd_dot(ray.direction, faceInfo.normal)

            // Skip back-facing faces (not visible from camera)
            if viewDot >= 0 {
                continue
            }

            // Ray-plane intersection
            let denom = viewDot
            let t = simd_dot(faceInfo.center - ray.origin, faceInfo.normal) / denom

            // Skip intersections behind ray origin
            if t < 0 {
                continue
            }

            let hitPoint = ray.origin + ray.direction * t

            // Check if hit point is within face bounds
            // For a unit cube centered at origin, check if hit point is within [-0.5, 0.5] on the two non-normal axes
            let abs_hp = abs(hitPoint)
            let abs_normal = abs(faceInfo.normal)

            // Check if point is within face bounds on the two perpendicular axes
            // When normal is along X axis (abs_normal.x >= 0.5), check Y and Z bounds
            // When normal is along Y axis (abs_normal.y >= 0.5), check X and Z bounds
            // When normal is along Z axis (abs_normal.z >= 0.5), check X and Y bounds
            let margin = Float(0.5)
            let inBounds = (abs_normal.x >= 0.5 && abs_hp.y <= margin && abs_hp.z <= margin) ||
                          (abs_normal.y >= 0.5 && abs_hp.x <= margin && abs_hp.z <= margin) ||
                          (abs_normal.z >= 0.5 && abs_hp.x <= margin && abs_hp.y <= margin)

            if inBounds && t < closestDistance {
                closestDistance = t
                closestFace = faceInfo.face
            }
        }

        return closestFace
    }
}
