import simd

/// Shader types shared between Swift and Metal shaders
/// Keep in sync with Shaders.metal

struct Uniforms {
    var modelMatrix: simd_float4x4
    var viewMatrix: simd_float4x4
    var projectionMatrix: simd_float4x4
    var normalMatrix: simd_float3x3
    var cameraPosition: simd_float3
    var viewportHeight: Float
    var _padding: SIMD2<Float> = .zero // Align to 16 bytes
}

struct MaterialProperties {
    var baseColor: simd_float3
    var glossiness: Float
    var metalness: Float
    var specularIntensity: Float
    var _padding1: SIMD2<Float> = .zero
    var _padding2: SIMD4<Float> = .zero // Extra padding to match Metal's 48-byte layout
}

struct VertexIn {
    var position: simd_float3
    var normal: simd_float3
    var color: simd_float4
    var texCoord: simd_float2 = .zero

    init(position: simd_float3, normal: simd_float3, color: simd_float4, texCoord: simd_float2 = .zero) {
        self.position = position
        self.normal = normal
        self.color = color
        self.texCoord = texCoord
    }
}

