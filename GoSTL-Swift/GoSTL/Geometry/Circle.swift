import Foundation

/// A circle in 3D space defined by center, radius, and normal
struct Circle {
    var center: Vector3
    var radius: Double
    var normal: Vector3

    // MARK: - Initializers

    init(center: Vector3, radius: Double, normal: Vector3) {
        self.center = center
        self.radius = radius
        self.normal = normal.normalized()
    }

    // MARK: - Circle Fitting

    /// Fit a circle to a set of 3D points using least-squares method
    /// - Parameters:
    ///   - points: Array of 3D points to fit
    ///   - constraintAxis: Optional axis constraint (0=X, 1=Y, 2=Z)
    ///   - tolerance: Maximum allowed deviation from the plane
    /// - Returns: Fitted circle, or nil if fitting fails
    static func fit(
        points: [Vector3],
        constraintAxis: Int? = nil,
        tolerance: Double = 0.1
    ) -> Circle? {
        guard points.count >= 3 else { return nil }

        // If we have exactly 3 points, use analytical solution
        if points.count == 3 {
            return fitThreePoints(points[0], points[1], points[2], constraintAxis: constraintAxis)
        }

        // For more points, use least-squares fitting
        return fitLeastSquares(points: points, constraintAxis: constraintAxis, tolerance: tolerance)
    }

    // MARK: - Private Fitting Methods

    /// Analytical circle fitting for exactly 3 points
    private static func fitThreePoints(
        _ p1: Vector3,
        _ p2: Vector3,
        _ p3: Vector3,
        constraintAxis: Int?
    ) -> Circle? {
        // Calculate plane normal
        let v1 = p2 - p1
        let v2 = p3 - p1
        var normal = v1.cross(v2).normalized()

        // If constrained to an axis, override normal
        if let axis = constraintAxis {
            switch axis {
            case 0: normal = Vector3.unitX
            case 1: normal = Vector3.unitY
            case 2: normal = Vector3.unitZ
            default: break
            }
        }

        // Calculate center as intersection of perpendicular bisectors
        let mid12 = (p1 + p2) * 0.5
        let mid23 = (p2 + p3) * 0.5

        let perp1 = (p2 - p1).cross(normal).normalized()
        let perp2 = (p3 - p2).cross(normal).normalized()

        // Solve for center using parametric line intersection
        // This is simplified; full implementation would use more robust method
        guard let center = lineIntersection(
            origin1: mid12, direction1: perp1,
            origin2: mid23, direction2: perp2,
            normal: normal
        ) else {
            return nil
        }

        let radius = center.distance(to: p1)

        // Verify the circle fits all three points
        let r2 = center.distance(to: p2)
        let r3 = center.distance(to: p3)

        guard abs(radius - r2) < 0.01 && abs(radius - r3) < 0.01 else {
            return nil
        }

        return Circle(center: center, radius: radius, normal: normal)
    }

    /// Least-squares circle fitting for multiple points
    private static func fitLeastSquares(
        points: [Vector3],
        constraintAxis: Int?,
        tolerance: Double
    ) -> Circle? {
        // Calculate centroid
        let centroid = points.reduce(Vector3.zero, +) / Double(points.count)

        // Determine plane normal
        var normal: Vector3
        if let axis = constraintAxis {
            // Use constrained axis
            switch axis {
            case 0: normal = Vector3.unitX
            case 1: normal = Vector3.unitY
            case 2: normal = Vector3.unitZ
            default: normal = Vector3.unitZ
            }
        } else {
            // Compute best-fit plane using covariance matrix (simplified)
            normal = computePlaneNormal(points: points, centroid: centroid)
        }

        // Project points onto plane
        let projected = points.map { projectToPlane($0, normal: normal, point: centroid) }

        // Find circle center in 2D (on the plane)
        guard let center2D = fit2DCircle(projected, centroid: centroid, normal: normal) else {
            return nil
        }

        // Calculate radius as average distance from center to projected points
        let distances = projected.map { center2D.distance(to: $0) }
        let radius = distances.reduce(0, +) / Double(distances.count)

        // Check if all points are within tolerance of the fitted circle
        let maxDeviation = distances.map { abs($0 - radius) }.max() ?? 0
        guard maxDeviation < tolerance else {
            return nil
        }

        return Circle(center: center2D, radius: radius, normal: normal)
    }

    /// Compute plane normal from points using PCA (simplified)
    private static func computePlaneNormal(points: [Vector3], centroid: Vector3) -> Vector3 {
        // Simplified: use first three points to define plane
        // Full implementation would use SVD/PCA
        guard points.count >= 3 else { return Vector3.unitZ }

        let v1 = points[1] - points[0]
        let v2 = points[2] - points[0]
        return v1.cross(v2).normalized()
    }

    /// Project point onto plane
    private static func projectToPlane(_ point: Vector3, normal: Vector3, point onPlane: Vector3) -> Vector3 {
        let v = point - onPlane
        let distance = v.dot(normal)
        return point - normal * distance
    }

    /// Fit circle in 2D (on the plane)
    private static func fit2DCircle(_ points: [Vector3], centroid: Vector3, normal: Vector3) -> Vector3? {
        guard points.count >= 3 else { return nil }

        // Simplified: use geometric median as approximation
        // Full implementation would use algebraic circle fitting
        var center = centroid

        // Iterative refinement (Weiszfeld's algorithm simplified)
        for _ in 0..<10 {
            var weightedSum = Vector3.zero
            var weights = 0.0

            for point in points {
                let dist = center.distance(to: point)
                if dist > 1e-10 {
                    let weight = 1.0 / dist
                    weightedSum = weightedSum + point * weight
                    weights += weight
                }
            }

            if weights > 0 {
                center = weightedSum / weights
            }
        }

        return center
    }

    /// Find intersection of two lines in 3D (constrained to a plane)
    private static func lineIntersection(
        origin1: Vector3, direction1: Vector3,
        origin2: Vector3, direction2: Vector3,
        normal: Vector3
    ) -> Vector3? {
        // Solve parametric line equations on the plane
        // Simplified implementation
        let cross = direction1.cross(direction2)

        guard cross.length > 1e-10 else {
            // Lines are parallel
            return nil
        }

        // Use geometric approach
        let w = origin1 - origin2
        let a = direction1.dot(direction1)
        let b = direction1.dot(direction2)
        let c = direction2.dot(direction2)
        let d = direction1.dot(w)
        let e = direction2.dot(w)

        let denom = a * c - b * b

        guard abs(denom) > 1e-10 else {
            return nil
        }

        let t = (b * e - c * d) / denom

        return origin1 + direction1 * t
    }
}

// MARK: - Codable

extension Circle: Codable {}

// MARK: - CustomStringConvertible

extension Circle: CustomStringConvertible {
    var description: String {
        String(format: "Circle(center: \(center), radius: %.3f, normal: \(normal))", radius)
    }
}
