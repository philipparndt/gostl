import Metal
import MetalKit
import CoreGraphics
import CoreText
import simd

/// Orientation for flat text quads
enum TextOrientation {
    case horizontal  // Flat on XZ plane (bottom grid)
    case verticalXY  // Flat on XY plane (back wall)
    case verticalYZ  // Flat on YZ plane (left wall)
}

/// GPU-ready flat text data for 3D text rendering
final class TextBillboardData {
    struct TextQuad {
        let position: SIMD3<Float>
        let texture: MTLTexture
        let size: Float
        let orientation: TextOrientation
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

            textQuads.append(TextQuad(
                position: label.position,
                texture: texture,
                size: label.size,
                orientation: label.orientation
            ))

            // Create flat quad vertices oriented according to the grid plane
            let halfSize = label.size / 2.0
            let pos = label.position
            let color = SIMD4<Float>(1, 1, 1, 1) // White, texture will provide color

            // Create quad based on orientation
            switch label.orientation {
            case .horizontal:
                // Flat on XZ plane (Y is up)
                vertices.append(contentsOf: TextBillboardData.createHorizontalQuad(pos: pos, halfSize: halfSize, color: color))
            case .verticalXY:
                // Flat on XY plane (Z is normal)
                vertices.append(contentsOf: TextBillboardData.createVerticalXYQuad(pos: pos, halfSize: halfSize, color: color))
            case .verticalYZ:
                // Flat on YZ plane (X is normal)
                vertices.append(contentsOf: TextBillboardData.createVerticalYZQuad(pos: pos, halfSize: halfSize, color: color))
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

    private static func createHorizontalQuad(pos: SIMD3<Float>, halfSize: Float, color: SIMD4<Float>) -> [VertexIn] {
        // Flat on XZ plane (laying on the ground)
        [
            // Triangle 1
            VertexIn(position: SIMD3(pos.x - halfSize, pos.y, pos.z - halfSize), normal: SIMD3(0, 1, 0), color: color, texCoord: SIMD2(0, 1)),
            VertexIn(position: SIMD3(pos.x + halfSize, pos.y, pos.z - halfSize), normal: SIMD3(0, 1, 0), color: color, texCoord: SIMD2(1, 1)),
            VertexIn(position: SIMD3(pos.x + halfSize, pos.y, pos.z + halfSize), normal: SIMD3(0, 1, 0), color: color, texCoord: SIMD2(1, 0)),
            // Triangle 2
            VertexIn(position: SIMD3(pos.x - halfSize, pos.y, pos.z - halfSize), normal: SIMD3(0, 1, 0), color: color, texCoord: SIMD2(0, 1)),
            VertexIn(position: SIMD3(pos.x + halfSize, pos.y, pos.z + halfSize), normal: SIMD3(0, 1, 0), color: color, texCoord: SIMD2(1, 0)),
            VertexIn(position: SIMD3(pos.x - halfSize, pos.y, pos.z + halfSize), normal: SIMD3(0, 1, 0), color: color, texCoord: SIMD2(0, 0))
        ]
    }

    private static func createVerticalXYQuad(pos: SIMD3<Float>, halfSize: Float, color: SIMD4<Float>) -> [VertexIn] {
        // Flat on XY plane (on the back wall) - facing toward positive Z
        [
            // Triangle 1
            VertexIn(position: SIMD3(pos.x - halfSize, pos.y - halfSize, pos.z), normal: SIMD3(0, 0, 1), color: color, texCoord: SIMD2(0, 0)),
            VertexIn(position: SIMD3(pos.x + halfSize, pos.y - halfSize, pos.z), normal: SIMD3(0, 0, 1), color: color, texCoord: SIMD2(1, 0)),
            VertexIn(position: SIMD3(pos.x + halfSize, pos.y + halfSize, pos.z), normal: SIMD3(0, 0, 1), color: color, texCoord: SIMD2(1, 1)),
            // Triangle 2
            VertexIn(position: SIMD3(pos.x - halfSize, pos.y - halfSize, pos.z), normal: SIMD3(0, 0, 1), color: color, texCoord: SIMD2(0, 0)),
            VertexIn(position: SIMD3(pos.x + halfSize, pos.y + halfSize, pos.z), normal: SIMD3(0, 0, 1), color: color, texCoord: SIMD2(1, 1)),
            VertexIn(position: SIMD3(pos.x - halfSize, pos.y + halfSize, pos.z), normal: SIMD3(0, 0, 1), color: color, texCoord: SIMD2(0, 1))
        ]
    }

    private static func createVerticalYZQuad(pos: SIMD3<Float>, halfSize: Float, color: SIMD4<Float>) -> [VertexIn] {
        // Flat on YZ plane (on the left wall)
        [
            // Triangle 1
            VertexIn(position: SIMD3(pos.x, pos.y - halfSize, pos.z - halfSize), normal: SIMD3(1, 0, 0), color: color, texCoord: SIMD2(0, 1)),
            VertexIn(position: SIMD3(pos.x, pos.y - halfSize, pos.z + halfSize), normal: SIMD3(1, 0, 0), color: color, texCoord: SIMD2(1, 1)),
            VertexIn(position: SIMD3(pos.x, pos.y + halfSize, pos.z + halfSize), normal: SIMD3(1, 0, 0), color: color, texCoord: SIMD2(1, 0)),
            // Triangle 2
            VertexIn(position: SIMD3(pos.x, pos.y - halfSize, pos.z - halfSize), normal: SIMD3(1, 0, 0), color: color, texCoord: SIMD2(0, 1)),
            VertexIn(position: SIMD3(pos.x, pos.y + halfSize, pos.z + halfSize), normal: SIMD3(1, 0, 0), color: color, texCoord: SIMD2(1, 0)),
            VertexIn(position: SIMD3(pos.x, pos.y + halfSize, pos.z - halfSize), normal: SIMD3(1, 0, 0), color: color, texCoord: SIMD2(0, 0))
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
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

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
