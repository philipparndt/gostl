#include <metal_stdlib>
using namespace metal;

// MARK: - Shader Types

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 color [[attribute(2)]];
    float2 texCoord [[attribute(3)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float3 modelNormal;  // Original normal in model space (for face orientation)
    float4 color;
    float3 worldPosition;
    float2 texCoord;
};

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3x3 normalMatrix;
    float3 cameraPosition;
    float viewportHeight;
    float2 _padding; // Align to 16 bytes
};

struct MaterialProperties {
    float3 baseColor;
    float glossiness;
    float metalness;
    float specularIntensity;
    float showFaceOrientation;  // 1.0 = show front/back face colors
    float _padding1;
    float4 _padding2; // Extra padding for proper alignment (total 48 bytes)
};

struct InstanceData {
    float4x4 modelMatrix;
    float4 color;
};

/// Per-instance data for wireframe edges with styling
struct WireframeInstance {
    float4x4 matrix;          // Transformation matrix for the edge
    float widthMultiplier;    // Width multiplier (1.0 = normal, 0.5 = thinner)
    float alpha;              // Alpha/transparency (1.0 = opaque, 0.3 = transparent)
    float2 _padding;          // Align to 16 bytes
};

// MARK: - Basic Shaders (Phase 0)

vertex VertexOut basicVertexShader(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 1.0);
    out.normal = in.normal;
    out.modelNormal = in.normal;
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
    out.modelNormal = in.normal;  // Pass original normal for face orientation
    out.worldPosition = worldPos.xyz;
    out.color = in.color; // Pre-baked lighting from Swift
    return out;
}

fragment float4 meshFragmentShader(
    VertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(0)]],
    constant MaterialProperties &material [[buffer(1)]]
) {
    // Normalize the interpolated normal
    float3 N = normalize(in.normal);

    // View direction (from fragment to camera)
    float3 V = normalize(uniforms.cameraPosition - in.worldPosition);

    // Check if face orientation mode is enabled
    if (material.showFaceOrientation > 0.5) {
        // Face orientation coloring: subtle color temperature shift
        // preserving the material's base color character
        // - Horizontal surfaces (facing up/down): slight cool tint
        // - Vertical/angled surfaces (facing sideways): slight warm/gold tint

        float3 base = material.baseColor;

        // Subtle cool tint for horizontal (slightly more blue)
        float3 coolTint = float3(-0.05, 0.0, 0.08);
        float3 horizontalColor = clamp(base + coolTint, 0.0, 1.0);

        // Subtle warm tint for vertical (slightly more gold/yellow)
        float3 warmTint = float3(0.12, 0.08, -0.15);
        float3 verticalColor = clamp(base + warmTint, 0.0, 1.0);

        // Use model-space normal (not view-transformed) for consistent coloring
        float3 modelN = normalize(in.modelNormal);

        // Check if surface is horizontal (normal pointing up or down)
        float zComponent = abs(modelN.z);

        // If Z dominates, it's a horizontal surface (top/bottom facing)
        // Threshold of 0.7 (~45 degrees from vertical)
        float3 baseColor = zComponent > 0.7 ? horizontalColor : verticalColor;

        // Apply full material lighting (same as normal mode)
        float3 keyLight = normalize(float3(0.5, 1.0, 0.5));
        float3 fillLight = normalize(float3(-0.5, 0.3, 0.8));
        float3 rimLight = normalize(float3(0.0, 0.5, -1.0));

        float keyDiffuse = max(0.0, dot(N, keyLight));
        float fillDiffuse = max(0.0, dot(N, fillLight));
        float rimDiffuse = max(0.0, dot(N, rimLight));

        float shininess = mix(8.0, 128.0, material.glossiness);
        float3 H_key = normalize(keyLight + V);
        float3 H_fill = normalize(fillLight + V);
        float3 H_rim = normalize(rimLight + V);

        float keySpecular = pow(max(0.0, dot(N, H_key)), shininess);
        float fillSpecular = pow(max(0.0, dot(N, H_fill)), shininess);
        float rimSpecular = pow(max(0.0, dot(N, H_rim)), shininess);

        float specular = (keySpecular * 0.6 + fillSpecular * 0.3 + rimSpecular * 0.2) * material.specularIntensity;
        float ambient = 0.3;
        float diffuse = keyDiffuse * 0.6 + fillDiffuse * 0.3 + rimDiffuse * 0.2;

        float3 finalColor = baseColor * (ambient + diffuse) + float3(specular);
        return float4(finalColor, 1.0);
    }

    // Normal rendering mode with full lighting

    // Three-light setup (same as pre-baked)
    float3 keyLight = normalize(float3(0.5, 1.0, 0.5));
    float3 fillLight = normalize(float3(-0.5, 0.3, 0.8));
    float3 rimLight = normalize(float3(0.0, 0.5, -1.0));

    // Diffuse lighting
    float keyDiffuse = max(0.0, dot(N, keyLight));
    float fillDiffuse = max(0.0, dot(N, fillLight));
    float rimDiffuse = max(0.0, dot(N, rimLight));

    // Specular lighting (Blinn-Phong)
    float shininess = mix(8.0, 128.0, material.glossiness); // Map glossiness to shininess

    float3 H_key = normalize(keyLight + V);
    float3 H_fill = normalize(fillLight + V);
    float3 H_rim = normalize(rimLight + V);

    float keySpecular = pow(max(0.0, dot(N, H_key)), shininess);
    float fillSpecular = pow(max(0.0, dot(N, H_fill)), shininess);
    float rimSpecular = pow(max(0.0, dot(N, H_rim)), shininess);

    // Combine specular contributions
    float specular = (keySpecular * 0.6 + fillSpecular * 0.3 + rimSpecular * 0.2) * material.specularIntensity;

    // Ambient + diffuse
    float ambient = 0.3;
    float diffuse = keyDiffuse * 0.6 + fillDiffuse * 0.3 + rimDiffuse * 0.2;

    // Determine base color:
    // - If vertex color is white (1,1,1), use material base color (single-color model)
    // - Otherwise, use vertex color directly (multi-color model like 3MF with extruders)
    float3 vertexColor = in.color.rgb;
    float isWhite = step(0.99, vertexColor.r) * step(0.99, vertexColor.g) * step(0.99, vertexColor.b);
    float3 baseColor = mix(vertexColor, material.baseColor, isWhite);

    // Final color = base color * (ambient + diffuse) + specular highlights
    float3 finalColor = baseColor * (ambient + diffuse) + float3(specular);

    return float4(finalColor, 1.0);
}

// MARK: - Wireframe Shaders (Phase 5 - Instanced rendering with screen-space sizing)

vertex VertexOut wireframeVertexShader(
    const VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    constant WireframeInstance *instances [[buffer(2)]],
    uint instanceID [[instance_id]]
) {
    VertexOut out;

    // Get instance data
    WireframeInstance instance = instances[instanceID];
    float4x4 instanceMatrix = instance.matrix;

    // Calculate edge position in world space
    float3 edgeStart = instanceMatrix[3].xyz;
    float distanceToCamera = length(uniforms.cameraPosition - edgeStart);

    // Calculate world-space size of 2 pixels at this distance
    // Extract FOV from projection matrix (assuming perspective projection)
    float fovY = 2.0 * atan(1.0 / uniforms.projectionMatrix[1][1]);
    float pixelSize = (distanceToCamera * tan(fovY * 0.5) * 2.0) / uniforms.viewportHeight;
    float wireframeThickness = pixelSize * 2.0 * instance.widthMultiplier; // Apply width multiplier

    // Scale the radius (XZ plane) while keeping length (Y axis)
    float3 scaledPosition = in.position;
    scaledPosition.x *= wireframeThickness;
    scaledPosition.z *= wireframeThickness;

    float4 worldPos = instanceMatrix * float4(scaledPosition, 1.0);

    // Apply view and projection
    worldPos = uniforms.modelMatrix * worldPos;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;

    // Transform normal
    float3x3 instanceRotation = float3x3(
        instanceMatrix[0].xyz,
        instanceMatrix[1].xyz,
        instanceMatrix[2].xyz
    );
    out.normal = uniforms.normalMatrix * instanceRotation * in.normal;
    out.modelNormal = in.normal;
    out.worldPosition = worldPos.xyz;

    // Apply alpha from instance
    out.color = float4(in.color.rgb, instance.alpha);

    return out;
}

fragment float4 wireframeFragmentShader(
    VertexOut in [[stage_in]]
) {
    return in.color;
}

// MARK: - Grid Shaders (Phase 6)

vertex VertexOut gridVertexShader(
    const VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.normal = uniforms.normalMatrix * in.normal;
    out.modelNormal = in.normal;
    out.worldPosition = worldPos.xyz;
    out.color = in.color;
    return out;
}

fragment float4 gridFragmentShader(
    VertexOut in [[stage_in]]
) {
    // Simple pass-through without distance fading
    return in.color;
}

// MARK: - Build Plate Shader (no distance fade)

fragment float4 buildPlateFragmentShader(
    VertexOut in [[stage_in]]
) {
    // Simple pass-through without distance fading
    return in.color;
}

// MARK: - Cut Edge Shaders (Phase 9 - Slicing)

vertex VertexOut cutEdgeVertexShader(
    const VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    constant InstanceData *instanceData [[buffer(2)]],
    uint instanceID [[instance_id]]
) {
    VertexOut out;

    // Get instance data
    InstanceData instance = instanceData[instanceID];
    float4x4 instanceMatrix = instance.modelMatrix;
    float4 instanceColor = instance.color;

    // Calculate pixel-perfect thickness (same as wireframe but 4x thicker)
    // Wireframe is 2 pixels, cut edges are 8 pixels
    float3 edgeStart = instanceMatrix[3].xyz;
    float distanceToCamera = length(uniforms.cameraPosition - edgeStart);

    // Calculate world-space size of 8 pixels at this distance
    float fovY = 2.0 * atan(1.0 / uniforms.projectionMatrix[1][1]);
    float pixelSize = (distanceToCamera * tan(fovY * 0.5) * 2.0) / uniforms.viewportHeight;
    float cutEdgeThickness = pixelSize * 8.0; // 8 pixels (4x wireframe)

    // Scale the radius (XZ plane) while keeping length (Y axis)
    float3 scaledPosition = in.position;
    scaledPosition.x *= cutEdgeThickness;
    scaledPosition.z *= cutEdgeThickness;

    // Transform position
    float4 worldPos = instanceMatrix * float4(scaledPosition, 1.0);
    worldPos = uniforms.modelMatrix * worldPos;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;

    // Transform normal
    float3x3 instanceRotation = float3x3(
        instanceMatrix[0].xyz,
        instanceMatrix[1].xyz,
        instanceMatrix[2].xyz
    );
    out.normal = uniforms.normalMatrix * instanceRotation * in.normal;
    out.modelNormal = in.normal;
    out.worldPosition = worldPos.xyz;

    // Use instance color instead of vertex color
    out.color = instanceColor;

    return out;
}

fragment float4 cutEdgeFragmentShader(
    VertexOut in [[stage_in]]
) {
    return in.color;
}

// MARK: - Textured Shaders (For 3D text labels)

vertex VertexOut texturedVertexShader(
    const VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.normal = uniforms.normalMatrix * in.normal;
    out.modelNormal = in.normal;
    out.worldPosition = worldPos.xyz;
    out.color = in.color;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 texturedFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> colorTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    // Sample the texture
    float4 texColor = colorTexture.sample(textureSampler, in.texCoord);

    // Multiply by vertex color (for tinting if needed)
    return texColor * in.color;
}
