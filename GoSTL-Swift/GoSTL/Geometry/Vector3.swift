import Foundation
import simd

/// A 3D vector backed by SIMD for hardware acceleration
struct Vector3 {
    var value: SIMD3<Double>

    // MARK: - Initializers

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.value = SIMD3(x, y, z)
    }

    init(value: SIMD3<Double>) {
        self.value = value
    }

    init() {
        self.value = SIMD3(0, 0, 0)
    }

    // MARK: - Accessors

    var x: Double {
        get { value.x }
        set { value.x = newValue }
    }

    var y: Double {
        get { value.y }
        set { value.y = newValue }
    }

    var z: Double {
        get { value.z }
        set { value.z = newValue }
    }

    // MARK: - Operations

    /// Addition
    static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(value: lhs.value + rhs.value)
    }

    /// Subtraction
    static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(value: lhs.value - rhs.value)
    }

    /// Scalar multiplication
    static func * (lhs: Vector3, rhs: Double) -> Vector3 {
        Vector3(value: lhs.value * rhs)
    }

    /// Scalar multiplication (reversed)
    static func * (lhs: Double, rhs: Vector3) -> Vector3 {
        Vector3(value: rhs.value * lhs)
    }

    /// Scalar division
    static func / (lhs: Vector3, rhs: Double) -> Vector3 {
        Vector3(value: lhs.value / rhs)
    }

    /// Negation
    static prefix func - (vector: Vector3) -> Vector3 {
        Vector3(value: -vector.value)
    }

    /// Dot product
    func dot(_ other: Vector3) -> Double {
        simd_dot(self.value, other.value)
    }

    /// Cross product
    func cross(_ other: Vector3) -> Vector3 {
        Vector3(value: simd_cross(self.value, other.value))
    }

    /// Length (magnitude) of the vector
    var length: Double {
        simd_length(value)
    }

    /// Squared length (avoids sqrt for performance)
    var lengthSquared: Double {
        simd_length_squared(value)
    }

    /// Returns a normalized (unit length) vector
    func normalized() -> Vector3 {
        let len = length
        guard len > 0 else { return Vector3() }
        return Vector3(value: simd_normalize(value))
    }

    /// Distance to another vector
    func distance(to other: Vector3) -> Double {
        simd_distance(self.value, other.value)
    }

    /// Squared distance (avoids sqrt for performance)
    func distanceSquared(to other: Vector3) -> Double {
        simd_distance_squared(self.value, other.value)
    }

    /// Component-wise minimum
    func min(_ other: Vector3) -> Vector3 {
        Vector3(value: simd_min(self.value, other.value))
    }

    /// Component-wise maximum
    func max(_ other: Vector3) -> Vector3 {
        Vector3(value: simd_max(self.value, other.value))
    }

    // MARK: - Conversion

    /// Convert to Float32 SIMD (for Metal shaders)
    var float3: SIMD3<Float> {
        SIMD3<Float>(Float(x), Float(y), Float(z))
    }
}

// MARK: - Equatable

extension Vector3: Equatable {
    static func == (lhs: Vector3, rhs: Vector3) -> Bool {
        lhs.value == rhs.value
    }

    /// Approximate equality with tolerance
    func isApproximatelyEqual(to other: Vector3, tolerance: Double = 1e-10) -> Bool {
        distance(to: other) < tolerance
    }
}

// MARK: - Hashable

extension Vector3: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
        hasher.combine(z)
    }
}

// MARK: - Codable

extension Vector3: Codable {
    enum CodingKeys: String, CodingKey {
        case x, y, z
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        let z = try container.decode(Double.self, forKey: .z)
        self.init(x, y, z)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(z, forKey: .z)
    }
}

// MARK: - CustomStringConvertible

extension Vector3: CustomStringConvertible {
    var description: String {
        String(format: "Vector3(%.3f, %.3f, %.3f)", x, y, z)
    }
}

// MARK: - Common Constants

extension Vector3 {
    static let zero = Vector3(0, 0, 0)
    static let one = Vector3(1, 1, 1)
    static let unitX = Vector3(1, 0, 0)
    static let unitY = Vector3(0, 1, 0)
    static let unitZ = Vector3(0, 0, 1)
}
