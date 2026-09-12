import Metal
import MetalKit
import CoreGraphics
import CoreText
import simd

/// Orientation for flat text quads (Z-up coordinate system)
enum TextOrientation {
    case horizontal  // Flat on XY plane (bottom grid, Z is up)
    case verticalXZ  // Flat on XZ plane (back wall, facing -Y)
    case verticalYZ  // Flat on YZ plane (left wall, facing +X)
    /// Facing the camera, upright on screen, whichever way the model is
    /// turned. A quad lying in a world plane reads mirrored from behind and
    /// upside down from below; a dimension has to be legible from anywhere.
    case billboard
}

/// GPU-ready flat text data for 3D text rendering
final class TextBillboardData {
    struct TextQuad {
        let position: SIMD3<Float>
        let texture: MTLTexture
        let size: Float
        let orientation: TextOrientation
        /// Width over height of the texture, so a quad made later - a
        /// billboard, per frame - keeps the text's proportions.
        let aspectRatio: Float
    }

    let vertexBuffer: MTLBuffer
    let textQuads: [TextQuad]
    let vertexCount: Int

    init(device: MTLDevice, labels: [(text: String, position: SIMD3<Float>, color: SIMD4<Float>, size: Float, orientation: TextOrientation)]) throws {
        var textQuads: [TextQuad] = []
        var vertices: [VertexIn] = []

        for label in labels {
            // Create texture for this text
            guard let texture = TextBillboardData.createTextTexture(
                device: device,
                text: label.text,
                color: label.color,
                fontSize: 48
            ) else {
                continue
            }

            // Calculate aspect ratio from texture dimensions
            let textureWidth = Float(texture.width)
            let textureHeight = Float(texture.height)
            let aspectRatio = textureWidth / textureHeight

            textQuads.append(TextQuad(
                position: label.position,
                texture: texture,
                size: label.size,
                orientation: label.orientation,
                aspectRatio: aspectRatio
            ))

            // Create flat quad vertices oriented according to the grid plane
            // Use aspect ratio to prevent text compression
            let halfHeight = label.size / 2.0
            let halfWidth = halfHeight * aspectRatio
            let pos = label.position
            let color = SIMD4<Float>(1, 1, 1, 1) // White, texture will provide color

            // Create quad based on orientation (Z-up coordinate system)
            switch label.orientation {
            case .horizontal:
                // Flat on XY plane (Z is up)
                vertices.append(contentsOf: TextBillboardData.createHorizontalQuad(pos: pos, halfWidth: halfWidth, halfHeight: halfHeight, color: color))
            case .verticalXZ:
                // Flat on XZ plane (back wall, facing -Y)
                vertices.append(contentsOf: TextBillboardData.createVerticalXZQuad(pos: pos, halfWidth: halfWidth, halfHeight: halfHeight, color: color))
            case .verticalYZ:
                // Flat on YZ plane (left wall, facing +X)
                vertices.append(contentsOf: TextBillboardData.createVerticalYZQuad(pos: pos, halfWidth: halfWidth, halfHeight: halfHeight, color: color))
            case .billboard:
                // Made at draw time from the camera; six placeholders keep
                // the buffer offsets of the quads after it where they are.
                vertices.append(contentsOf: TextBillboardData.createHorizontalQuad(pos: pos, halfWidth: 0, halfHeight: 0, color: color))
            }
        }

        self.textQuads = textQuads
        self.vertexCount = vertices.count

        // Create GPU buffer
        guard !vertices.isEmpty else {
            throw MetalError.bufferCreationFailed
        }

        let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
        guard let buffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: []) else {
            throw MetalError.bufferCreationFailed
        }
        self.vertexBuffer = buffer
    }

    // MARK: - Quad Generation

    /// A quad facing the camera, its edges along the screen's, sized in world
    /// units like the flat ones. Made every frame because the camera moves.
    static func createBillboardQuad(pos: SIMD3<Float>, halfWidth: Float, halfHeight: Float, camera: Camera) -> [VertexIn] {
        let view = camera.viewMatrix()
        // The view matrix's rows are the camera axes in world space.
        let right = simd_normalize(SIMD3<Float>(view[0][0], view[1][0], view[2][0]))
        let up = simd_normalize(SIMD3<Float>(view[0][1], view[1][1], view[2][1]))
        let normal = simd_normalize(camera.position - pos)
        let color = SIMD4<Float>(1, 1, 1, 1)

        let v0 = pos - right * halfWidth - up * halfHeight
        let v1 = pos + right * halfWidth - up * halfHeight
        let v2 = pos + right * halfWidth + up * halfHeight
        let v3 = pos - right * halfWidth + up * halfHeight

        // The same texture mapping as the flat quad on the ground: v = 1 is
        // the top of the text.
        return [
            VertexIn(position: v0, normal: normal, color: color, texCoord: SIMD2(0, 0)),
            VertexIn(position: v1, normal: normal, color: color, texCoord: SIMD2(1, 0)),
            VertexIn(position: v2, normal: normal, color: color, texCoord: SIMD2(1, 1)),
            VertexIn(position: v0, normal: normal, color: color, texCoord: SIMD2(0, 0)),
            VertexIn(position: v2, normal: normal, color: color, texCoord: SIMD2(1, 1)),
            VertexIn(position: v3, normal: normal, color: color, texCoord: SIMD2(0, 1))
        ]
    }

    /// Horizontal text on XY plane (Z-up: text lies flat on ground, readable from above)
    private static func createHorizontalQuad(pos: SIMD3<Float>, halfWidth: Float, halfHeight: Float, color: SIMD4<Float>) -> [VertexIn] {
        // Flat on XY plane (Z is up)
        // X direction = width, Y direction = height (depth)
        // Text readable when viewed from front (-Y looking toward +Y)
        [
            // Triangle 1
            VertexIn(position: SIMD3(pos.x - halfWidth, pos.y - halfHeight, pos.z), normal: SIMD3(0, 0, 1), color: color, texCoord: SIMD2(0, 0)),
            VertexIn(position: SIMD3(pos.x + halfWidth, pos.y - halfHeight, pos.z), normal: SIMD3(0, 0, 1), color: color, texCoord: SIMD2(1, 0)),
            VertexIn(position: SIMD3(pos.x + halfWidth, pos.y + halfHeight, pos.z), normal: SIMD3(0, 0, 1), color: color, texCoord: SIMD2(1, 1)),
            // Triangle 2
            VertexIn(position: SIMD3(pos.x - halfWidth, pos.y - halfHeight, pos.z), normal: SIMD3(0, 0, 1), color: color, texCoord: SIMD2(0, 0)),
            VertexIn(position: SIMD3(pos.x + halfWidth, pos.y + halfHeight, pos.z), normal: SIMD3(0, 0, 1), color: color, texCoord: SIMD2(1, 1)),
            VertexIn(position: SIMD3(pos.x - halfWidth, pos.y + halfHeight, pos.z), normal: SIMD3(0, 0, 1), color: color, texCoord: SIMD2(0, 1))
        ]
    }

    /// Vertical text on XZ plane (Z-up: back wall, facing toward viewer at -Y)
    private static func createVerticalXZQuad(pos: SIMD3<Float>, halfWidth: Float, halfHeight: Float, color: SIMD4<Float>) -> [VertexIn] {
        // Flat on XZ plane (Y is normal, facing -Y toward viewer)
        // X direction = width, Z direction = height (up)
        [
            // Triangle 1
            VertexIn(position: SIMD3(pos.x - halfWidth, pos.y, pos.z - halfHeight), normal: SIMD3(0, -1, 0), color: color, texCoord: SIMD2(0, 1)),
            VertexIn(position: SIMD3(pos.x + halfWidth, pos.y, pos.z - halfHeight), normal: SIMD3(0, -1, 0), color: color, texCoord: SIMD2(1, 1)),
            VertexIn(position: SIMD3(pos.x + halfWidth, pos.y, pos.z + halfHeight), normal: SIMD3(0, -1, 0), color: color, texCoord: SIMD2(1, 0)),
            // Triangle 2
            VertexIn(position: SIMD3(pos.x - halfWidth, pos.y, pos.z - halfHeight), normal: SIMD3(0, -1, 0), color: color, texCoord: SIMD2(0, 1)),
            VertexIn(position: SIMD3(pos.x + halfWidth, pos.y, pos.z + halfHeight), normal: SIMD3(0, -1, 0), color: color, texCoord: SIMD2(1, 0)),
            VertexIn(position: SIMD3(pos.x - halfWidth, pos.y, pos.z + halfHeight), normal: SIMD3(0, -1, 0), color: color, texCoord: SIMD2(0, 0))
        ]
    }

    /// Vertical text on YZ plane (Z-up: left wall, facing +X toward viewer)
    private static func createVerticalYZQuad(pos: SIMD3<Float>, halfWidth: Float, halfHeight: Float, color: SIMD4<Float>) -> [VertexIn] {
        // Flat on YZ plane (X is normal, facing +X)
        // Y direction = width, Z direction = height (up)
        [
            // Triangle 1
            VertexIn(position: SIMD3(pos.x, pos.y - halfWidth, pos.z - halfHeight), normal: SIMD3(1, 0, 0), color: color, texCoord: SIMD2(0, 1)),
            VertexIn(position: SIMD3(pos.x, pos.y + halfWidth, pos.z - halfHeight), normal: SIMD3(1, 0, 0), color: color, texCoord: SIMD2(1, 1)),
            VertexIn(position: SIMD3(pos.x, pos.y + halfWidth, pos.z + halfHeight), normal: SIMD3(1, 0, 0), color: color, texCoord: SIMD2(1, 0)),
            // Triangle 2
            VertexIn(position: SIMD3(pos.x, pos.y - halfWidth, pos.z - halfHeight), normal: SIMD3(1, 0, 0), color: color, texCoord: SIMD2(0, 1)),
            VertexIn(position: SIMD3(pos.x, pos.y + halfWidth, pos.z + halfHeight), normal: SIMD3(1, 0, 0), color: color, texCoord: SIMD2(1, 0)),
            VertexIn(position: SIMD3(pos.x, pos.y - halfWidth, pos.z + halfHeight), normal: SIMD3(1, 0, 0), color: color, texCoord: SIMD2(0, 0))
        ]
    }

    // MARK: - Text Rendering

    private static func createTextTexture(
        device: MTLDevice,
        text: String,
        color: SIMD4<Float>,
        fontSize: CGFloat
    ) -> MTLTexture? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor(
                red: CGFloat(color.x),
                green: CGFloat(color.y),
                blue: CGFloat(color.z),
                alpha: CGFloat(color.w)
            )
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        // Add padding
        let padding: CGFloat = 8
        let width = Int(ceil(textSize.width + padding * 2))
        let height = Int(ceil(textSize.height + padding * 2))

        // Create bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Clear background (fully transparent)
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Configure rendering for clean transparency
        context.setBlendMode(.normal)
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false) // Disable subpixel antialiasing for transparent backgrounds

        // Draw text
        context.textMatrix = .identity
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)

        let line = CTLineCreateWithAttributedString(attributedString)
        context.textPosition = CGPoint(x: padding, y: padding)
        CTLineDraw(line, context)

        // Create Metal texture
        guard let data = context.data else {
            return nil
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: width * 4
        )

        return texture
    }
}
