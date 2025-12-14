import Foundation
import simd

/// Utilities for rotation transformations
struct Rotation {
    /// Calculate the rotation needed to level two points along a specific axis.
    /// After rotation, both points will have the same coordinate on the target axis.
    ///
    /// - Parameters:
    ///   - point1: First reference point
    ///   - point2: Second reference point
    ///   - targetAxis: The axis to level (0=X, 1=Y, 2=Z)
    ///   - center: Center point for rotation
    /// - Returns: Tuple of (rotation axis, rotation angle in radians)
    static func calculateLevelingRotation(
        point1: Vector3,
        point2: Vector3,
        targetAxis: Int,
        center: Vector3
    ) -> (axis: Vector3, angle: Double) {
        // Vector from point1 to point2
        let direction = point2 - point1
        let dirLength = direction.length

        // If points are too close, no rotation needed
        guard dirLength > 1e-10 else {
            return (Vector3.unitX, 0)
        }

        // Get the component of the direction vector along the target axis
        let axisComponents: [Double]
        switch targetAxis {
        case 0: axisComponents = [1, 0, 0]  // X axis - want same X
        case 1: axisComponents = [0, 1, 0]  // Y axis - want same Y
        case 2: axisComponents = [0, 0, 1]  // Z axis - want same Z
        default: return (Vector3.unitX, 0)
        }

        let targetNormal = Vector3(axisComponents[0], axisComponents[1], axisComponents[2])

        // The component of direction along the target axis
        let axisComponent = direction.dot(targetNormal)

        // If the axis component is already zero (or very close), points are already level
        if abs(axisComponent) < 1e-10 {
            return (Vector3.unitX, 0)
        }

        // We need to rotate the direction vector so its component along targetNormal becomes zero.
        // The rotation axis should be perpendicular to both the target axis and the direction vector.
        // Actually, we need to find the plane perpendicular to targetNormal and project direction onto it.

        // Project direction onto the plane perpendicular to targetNormal
        let projectedDirection = direction - targetNormal * axisComponent

        // If the projected direction is zero (direction is parallel to target axis),
        // any rotation axis perpendicular to target axis will work
        if projectedDirection.length < 1e-10 {
            // Direction is parallel to target axis, need to rotate 90 degrees
            // Pick a rotation axis perpendicular to target
            let rotAxis: Vector3
            switch targetAxis {
            case 0: rotAxis = Vector3.unitY  // For X, rotate around Y
            case 1: rotAxis = Vector3.unitX  // For Y, rotate around X
            default: rotAxis = Vector3.unitX  // For Z, rotate around X
            }
            let angle = axisComponent > 0 ? Double.pi / 2 : -Double.pi / 2
            return (rotAxis, angle)
        }

        // The rotation axis is perpendicular to the plane containing direction and projectedDirection
        let rotationAxis = direction.cross(projectedDirection).normalized()

        // If rotation axis is zero, directions are parallel (shouldn't happen at this point)
        guard rotationAxis.length > 1e-10 else {
            return (Vector3.unitX, 0)
        }

        // Angle between direction and projected direction
        let dirNormalized = direction.normalized()
        let projNormalized = projectedDirection.normalized()
        let dotProduct = dirNormalized.dot(projNormalized)
        let clampedDot = Swift.max(-1.0, Swift.min(1.0, dotProduct))
        let angle = acos(clampedDot)

        // Determine sign of angle based on the axis component
        // If axis component is positive, we need to rotate to reduce it (negative rotation)
        // If axis component is negative, we need to rotate to increase it (positive rotation)
        let signedAngle = axisComponent > 0 ? -angle : angle

        return (rotationAxis, signedAngle)
    }

    /// Apply rotation to a point around a center using Rodrigues' rotation formula
    ///
    /// - Parameters:
    ///   - point: The point to rotate
    ///   - axis: The normalized rotation axis
    ///   - angle: Rotation angle in radians
    ///   - center: Center of rotation
    /// - Returns: The rotated point
    static func rotatePoint(
        _ point: Vector3,
        axis: Vector3,
        angle: Double,
        center: Vector3
    ) -> Vector3 {
        // Translate point to origin (center becomes origin)
        let p = point - center

        // Rodrigues' rotation formula:
        // v_rot = v*cos(θ) + (k × v)*sin(θ) + k*(k·v)*(1-cos(θ))
        // where k is the rotation axis (unit vector) and θ is the angle

        let cosA = cos(angle)
        let sinA = sin(angle)

        // k × v (cross product)
        let crossProduct = axis.cross(p)

        // k · v (dot product)
        let dotProduct = axis.dot(p)

        // Apply formula
        let rotated = p * cosA + crossProduct * sinA + axis * dotProduct * (1 - cosA)

        // Translate back
        return rotated + center
    }

    /// Apply rotation to an entire model
    ///
    /// - Parameters:
    ///   - model: The model to transform (modified in place)
    ///   - axis: The normalized rotation axis
    ///   - angle: Rotation angle in radians
    ///   - center: Center of rotation
    static func rotateModel(
        _ model: inout STLModel,
        axis: Vector3,
        angle: Double,
        center: Vector3
    ) {
        // Skip if angle is negligible
        guard abs(angle) > 1e-10 else { return }

        // Transform all triangles
        for i in 0..<model.triangles.count {
            // Rotate each vertex
            model.triangles[i].v1 = rotatePoint(model.triangles[i].v1, axis: axis, angle: angle, center: center)
            model.triangles[i].v2 = rotatePoint(model.triangles[i].v2, axis: axis, angle: angle, center: center)
            model.triangles[i].v3 = rotatePoint(model.triangles[i].v3, axis: axis, angle: angle, center: center)

            // Update normal after vertex transformation
            model.triangles[i].updateNormal()
        }
    }
}
