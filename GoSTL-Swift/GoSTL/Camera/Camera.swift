import Foundation
import simd

/// Spherical camera controller for 3D navigation
@Observable
final class Camera {
    // MARK: - Camera State

    /// Distance from target
    var distance: Double = 100.0

    /// Pitch angle (rotation around X-axis), in radians
    var angleX: Double = 0.3

    /// Yaw angle (rotation around Y-axis), in radians
    var angleY: Double = 0.5

    /// Target point to orbit around
    var target: SIMD3<Float> = .zero

    // Default values for reset
    private var defaultDistance: Double = 100.0
    private var defaultAngleX: Double = 0.3
    private var defaultAngleY: Double = 0.5
    private var defaultTarget: SIMD3<Float> = .zero

    // MARK: - Computed Properties

    /// Camera position in world space (calculated from spherical coordinates)
    var position: SIMD3<Float> {
        let x = Float(distance * cos(angleX) * sin(angleY))
        let y = Float(distance * sin(angleX))
        let z = Float(distance * cos(angleX) * cos(angleY))
        return target + SIMD3(x, y, z)
    }

    /// Up vector for the camera
    var up: SIMD3<Float> {
        SIMD3(0, 1, 0)
    }

    // MARK: - Matrix Generation

    /// Generate view matrix (lookAt)
    func viewMatrix() -> simd_float4x4 {
        matrix_lookAt(eye: position, center: target, up: up)
    }

    /// Generate projection matrix
    func projectionMatrix(aspect: Float, fov: Float = .pi / 4, near: Float = 0.1, far: Float = 1000.0) -> simd_float4x4 {
        matrix_perspective(fov: fov, aspect: aspect, near: near, far: far)
    }

    // MARK: - Camera Manipulation

    /// Rotate camera
    func rotate(deltaX: Double, deltaY: Double) {
        angleX += deltaX
        angleY += deltaY

        // Clamp pitch to avoid gimbal lock
        angleX = max(-Double.pi / 2 + 0.1, min(Double.pi / 2 - 0.1, angleX))
    }

    /// Zoom camera (adjust distance)
    func zoom(delta: Double) {
        distance += delta
        distance = max(1.0, min(1000.0, distance)) // Clamp to reasonable range
    }

    /// Pan camera (move target)
    func pan(delta: SIMD2<Float>) {
        let right = simd_normalize(simd_cross(target - position, up))
        let upLocal = simd_normalize(simd_cross(right, target - position))

        target += right * delta.x + upLocal * delta.y
    }

    /// Reset to default view
    func reset() {
        distance = defaultDistance
        angleX = defaultAngleX
        angleY = defaultAngleY
        target = defaultTarget
    }

    /// Set camera to a preset view
    func setPreset(_ preset: CameraPreset) {
        let (x, y) = preset.angles
        angleX = x
        angleY = y
    }

    /// Save current view as default
    func saveAsDefault() {
        defaultDistance = distance
        defaultAngleX = angleX
        defaultAngleY = angleY
        defaultTarget = target
    }

    /// Frame a bounding box in view
    func frameBoundingBox(_ bbox: BoundingBox) {
        // Set target to center of bounding box
        target = bbox.center.float3

        // Set distance based on bounding box size
        let size = bbox.diagonal
        distance = size * 1.5 // Factor to ensure entire model is visible

        // Save as new default
        saveAsDefault()
    }

    // MARK: - Ray Casting

    /// Generate a ray from screen coordinates
    func mouseRay(screenPos: CGPoint, viewSize: CGSize) -> Ray {
        let aspect = Float(viewSize.width / viewSize.height)
        let projection = projectionMatrix(aspect: aspect)
        let view = viewMatrix()

        // Convert screen coordinates to normalized device coordinates (NDC)
        // NSView has Y=0 at bottom, NDC has Y=-1 at bottom, Y=+1 at top
        let x = Float((2.0 * screenPos.x) / viewSize.width - 1.0)
        let y = Float((2.0 * screenPos.y) / viewSize.height - 1.0) // No flip needed for NSView

        // Ray in clip space
        let rayClip = SIMD4<Float>(x, y, -1.0, 1.0)

        // Ray in eye space
        let rayEye = projection.inverse * rayClip
        let rayEye3 = SIMD4<Float>(rayEye.x, rayEye.y, -1.0, 0.0)

        // Ray in world space
        let rayWorld4 = view.inverse * rayEye3
        let rayWorld = SIMD3<Float>(rayWorld4.x, rayWorld4.y, rayWorld4.z)
        let direction = simd_normalize(rayWorld)

        return Ray(origin: position, direction: direction)
    }

    /// Project a 3D world position to 2D screen coordinates
    /// - Returns: CGPoint in screen coordinates, or nil if behind camera
    func project(worldPosition: Vector3, viewSize: CGSize) -> CGPoint? {
        let aspect = Float(viewSize.width / viewSize.height)
        let projection = projectionMatrix(aspect: aspect)
        let view = viewMatrix()

        // Transform world position to clip space
        let worldPos4 = SIMD4<Float>(worldPosition.float3, 1.0)
        let clipPos = projection * view * worldPos4

        // Check if behind camera
        if clipPos.w <= 0 {
            return nil
        }

        // Perspective divide to get NDC
        let ndc = SIMD3<Float>(clipPos.x, clipPos.y, clipPos.z) / clipPos.w

        // Check if outside view frustum (X and Y only)
        if abs(ndc.x) > 1.0 || abs(ndc.y) > 1.0 {
            return nil
        }

        // Convert NDC to screen coordinates
        // SwiftUI overlay has Y=0 at top, so we flip Y
        let screenX = (Double(ndc.x) + 1.0) * 0.5 * viewSize.width
        let screenY = (1.0 - Double(ndc.y)) * 0.5 * viewSize.height  // Flip Y for SwiftUI

        return CGPoint(x: screenX, y: screenY)
    }
}

// MARK: - Camera Presets

enum CameraPreset {
    case top
    case bottom
    case front
    case back
    case left
    case right
    case home

    var angles: (x: Double, y: Double) {
        switch self {
        case .top:
            return (Double.pi / 2 - 0.1, 0)
        case .bottom:
            return (-Double.pi / 2 + 0.1, 0)
        case .front:
            return (0, 0)
        case .back:
            return (0, Double.pi)
        case .left:
            return (0, -Double.pi / 2)
        case .right:
            return (0, Double.pi / 2)
        case .home:
            return (0.3, 0.5)
        }
    }
}

// MARK: - Ray

struct Ray {
    var origin: SIMD3<Float>
    var direction: SIMD3<Float>

    /// Find the closest point on the ray to a given point
    func closestPoint(to point: SIMD3<Float>) -> SIMD3<Float> {
        let v = point - origin
        let t = simd_dot(v, direction)
        return origin + direction * max(0, t)
    }

    /// Distance from ray to a point
    func distance(to point: SIMD3<Float>) -> Float {
        let closest = closestPoint(to: point)
        return simd_distance(closest, point)
    }
}

// MARK: - Matrix Utilities

/// Create a lookAt view matrix
func matrix_lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
    let z = simd_normalize(eye - center)
    let x = simd_normalize(simd_cross(up, z))
    let y = simd_cross(z, x)

    return simd_float4x4(
        SIMD4(x.x, y.x, z.x, 0),
        SIMD4(x.y, y.y, z.y, 0),
        SIMD4(x.z, y.z, z.z, 0),
        SIMD4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
    )
}

/// Create a perspective projection matrix
func matrix_perspective(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let tanHalfFov = tan(fov / 2)

    var matrix = simd_float4x4(0)
    matrix[0][0] = 1 / (aspect * tanHalfFov)
    matrix[1][1] = 1 / tanHalfFov
    matrix[2][2] = -(far + near) / (far - near)
    matrix[2][3] = -1
    matrix[3][2] = -(2 * far * near) / (far - near)

    return matrix
}

/// Get the inverse of a 4x4 matrix
extension simd_float4x4 {
    var inverse: simd_float4x4 {
        simd_inverse(self)
    }
}
