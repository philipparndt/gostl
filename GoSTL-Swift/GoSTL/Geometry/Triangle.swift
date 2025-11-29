import Foundation
import simd

/// A triangle defined by three vertices
struct Triangle {
    var v1: Vector3
    var v2: Vector3
    var v3: Vector3
    var normal: Vector3

    // MARK: - Initializers

    init(v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3? = nil) {
        self.v1 = v1
        self.v2 = v2
        self.v3 = v3
        self.normal = normal ?? Self.calculateNormal(v1: v1, v2: v2, v3: v3)
    }

    // MARK: - Computed Properties

    /// Calculate the normal vector from vertices (cross product)
    static func calculateNormal(v1: Vector3, v2: Vector3, v3: Vector3) -> Vector3 {
        let edge1 = v2 - v1
        let edge2 = v3 - v1
        return edge1.cross(edge2).normalized()
    }

    /// Recalculate normal from current vertices
    mutating func updateNormal() {
        self.normal = Self.calculateNormal(v1: v1, v2: v2, v3: v3)
    }

    /// Area of the triangle
    func area() -> Double {
        let edge1 = v2 - v1
        let edge2 = v3 - v1
        return edge1.cross(edge2).length * 0.5
    }

    /// Length of each edge
    func edgeLengths() -> (Double, Double, Double) {
        let e1 = v1.distance(to: v2)
        let e2 = v2.distance(to: v3)
        let e3 = v3.distance(to: v1)
        return (e1, e2, e3)
    }

    /// Perimeter (sum of edge lengths)
    func perimeter() -> Double {
        let edges = edgeLengths()
        return edges.0 + edges.1 + edges.2
    }

    /// Centroid (center point)
    func center() -> Vector3 {
        (v1 + v2 + v3) / 3.0
    }

    /// Interior angles in radians
    func angles() -> (Double, Double, Double) {
        let a = v2 - v1
        let b = v3 - v1
        let c = v3 - v2

        let angle1 = acos(a.dot(b) / (a.length * b.length))
        let angle2 = acos((-a).dot(c) / (a.length * c.length))
        let angle3 = .pi - angle1 - angle2

        return (angle1, angle2, angle3)
    }

    /// All three vertices as an array
    var vertices: [Vector3] {
        [v1, v2, v3]
    }

    // MARK: - Ray Intersection

    /// Ray-triangle intersection using Möller–Trumbore algorithm
    /// - Parameter ray: The ray to test
    /// - Returns: Distance along the ray where intersection occurs, or nil if no intersection
    func intersect(ray: Ray) -> Float? {
        let epsilon: Float = 1e-6

        // Convert to Float for ray calculations
        let v1f = v1.float3
        let v2f = v2.float3
        let v3f = v3.float3

        let edge1 = v2f - v1f
        let edge2 = v3f - v1f
        let h = simd_cross(ray.direction, edge2)
        let a = simd_dot(edge1, h)

        // Ray is parallel to triangle
        if abs(a) < epsilon {
            return nil
        }

        let f = 1.0 / a
        let s = ray.origin - v1f
        let u = f * simd_dot(s, h)

        // Intersection point is outside triangle
        if u < 0.0 || u > 1.0 {
            return nil
        }

        let q = simd_cross(s, edge1)
        let v = f * simd_dot(ray.direction, q)

        // Intersection point is outside triangle
        if v < 0.0 || u + v > 1.0 {
            return nil
        }

        // Calculate t (distance along ray)
        let t = f * simd_dot(edge2, q)

        // Intersection is behind the ray origin
        if t < epsilon {
            return nil
        }

        return t
    }

    /// Get the point and normal at an intersection
    /// - Parameter ray: The ray to test
    /// - Returns: Tuple of (position, normal) if intersection occurs
    func intersectionPoint(ray: Ray) -> (position: Vector3, normal: Vector3)? {
        guard let t = intersect(ray: ray) else {
            return nil
        }
        let positionFloat = ray.origin + ray.direction * t
        let hitPoint = Vector3(Double(positionFloat.x), Double(positionFloat.y), Double(positionFloat.z))

        // Snap to nearest vertex
        let vertices = [v1, v2, v3]
        let distances = vertices.map { $0.distance(to: hitPoint) }
        let minIndex = distances.enumerated().min(by: { $0.element < $1.element })!.offset
        let snappedPosition = vertices[minIndex]

        return (snappedPosition, normal)
    }
}

// MARK: - Equatable

extension Triangle: Equatable {
    static func == (lhs: Triangle, rhs: Triangle) -> Bool {
        lhs.v1 == rhs.v1 &&
        lhs.v2 == rhs.v2 &&
        lhs.v3 == rhs.v3
    }
}

// MARK: - Codable

extension Triangle: Codable {
    enum CodingKeys: String, CodingKey {
        case v1, v2, v3, normal
    }
}

// MARK: - CustomStringConvertible

extension Triangle: CustomStringConvertible {
    var description: String {
        "Triangle(\(v1), \(v2), \(v3))"
    }
}
