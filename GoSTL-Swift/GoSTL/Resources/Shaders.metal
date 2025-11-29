#include <metal_stdlib>
using namespace metal;

// MARK: - Shader Types

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 color [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float4 color;
    float3 worldPosition;
};

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3x3 normalMatrix;
    float3 cameraPosition;
};

// MARK: - Basic Shaders (Phase 0)

vertex VertexOut basicVertexShader(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 1.0);
    out.normal = in.normal;
    out.color = float4(1.0, 0.0, 0.0, 1.0); // Red
    out.worldPosition = in.position;
    return out;
}

fragment float4 basicFragmentShader(VertexOut in [[stage_in]]) {
    return in.color;
}

// MARK: - Mesh Shaders (Phase 4 - placeholder)

vertex VertexOut meshVertexShader(
    const VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.normal = uniforms.normalMatrix * in.normal;
    out.worldPosition = worldPos.xyz;
    out.color = in.color; // Pre-baked lighting from Swift
    return out;
}

fragment float4 meshFragmentShader(
    VertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(0)]]
) {
    return in.color; // Lighting already baked into vertex colors
}
