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

/// GPU data for rendering the orientation cube
final class OrientationCubeData {
    let device: MTLDevice
    let vertexBuffer: MTLBuffer
    let vertexCount: Int

    // Text rendering data
    let textVertexBuffer: MTLBuffer?
    let textTextures: [(texture: MTLTexture, vertexOffset: Int)]

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
