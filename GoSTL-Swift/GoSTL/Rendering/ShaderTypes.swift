import simd

/// Shader types shared between Swift and Metal shaders
/// Keep in sync with Shaders.metal

struct Uniforms {
    var modelMatrix: simd_float4x4
    var viewMatrix: simd_float4x4
    var projectionMatrix: simd_float4x4
    var normalMatrix: simd_float3x3
    var cameraPosition: simd_float3
}

struct VertexIn {
    var position: simd_float3
    var normal: simd_float3
    var color: simd_float4
}
