import Foundation

/// An axis-aligned bounding box (AABB)
struct BoundingBox {
    var min: Vector3
    var max: Vector3

    // MARK: - Initializers

    init(min: Vector3 = Vector3.zero, max: Vector3 = Vector3.zero) {
        self.min = min
        self.max = max
    }

    /// Create from a single point
    init(point: Vector3) {
        self.min = point
        self.max = point
    }

    /// Create from a collection of points
    init(points: [Vector3]) {
        guard let first = points.first else {
            self.min = .zero
            self.max = .zero
            return
        }

        var box = BoundingBox(point: first)
        for point in points.dropFirst() {
            box.extend(point)
        }
        self = box
    }

    // MARK: - Mutations

    /// Extend the bounding box to include a point
    mutating func extend(_ point: Vector3) {
        min = min.min(point)
        max = max.max(point)
    }

    /// Extend the bounding box to include another box
    mutating func extend(_ other: BoundingBox) {
        min = min.min(other.min)
        max = max.max(other.max)
    }

    // MARK: - Computed Properties

    /// Size (dimensions) of the bounding box
    var size: Vector3 {
        max - min
    }

    /// Center point of the bounding box
    var center: Vector3 {
        (min + max) * 0.5
    }

    /// Diagonal length
    var diagonal: Double {
        size.length
    }

    /// Volume of the bounding box
    var volume: Double {
        let s = size
        return s.x * s.y * s.z
    }

    /// Surface area of the bounding box
    var surfaceArea: Double {
        let s = size
        return 2.0 * (s.x * s.y + s.y * s.z + s.z * s.x)
    }

    /// Check if the box contains a point
    func contains(_ point: Vector3) -> Bool {
        point.x >= min.x && point.x <= max.x &&
        point.y >= min.y && point.y <= max.y &&
        point.z >= min.z && point.z <= max.z
    }

    /// Check if this box intersects another box
    func intersects(_ other: BoundingBox) -> Bool {
        min.x <= other.max.x && max.x >= other.min.x &&
        min.y <= other.max.y && max.y >= other.min.y &&
        min.z <= other.max.z && max.z >= other.min.z
    }

    /// All 8 corners of the bounding box
    var corners: [Vector3] {
        [
            Vector3(min.x, min.y, min.z),
            Vector3(max.x, min.y, min.z),
            Vector3(min.x, max.y, min.z),
            Vector3(max.x, max.y, min.z),
            Vector3(min.x, min.y, max.z),
            Vector3(max.x, min.y, max.z),
            Vector3(min.x, max.y, max.z),
            Vector3(max.x, max.y, max.z),
        ]
    }
}

// MARK: - Equatable

extension BoundingBox: Equatable {
    static func == (lhs: BoundingBox, rhs: BoundingBox) -> Bool {
        lhs.min == rhs.min && lhs.max == rhs.max
    }
}

// MARK: - Codable

extension BoundingBox: Codable {}

// MARK: - CustomStringConvertible

extension BoundingBox: CustomStringConvertible {
    var description: String {
        "BoundingBox(min: \(min), max: \(max), size: \(size))"
    }
}
