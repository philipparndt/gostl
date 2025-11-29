import XCTest
@testable import GoSTL

final class Vector3Tests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitialization() {
        let v = Vector3(1, 2, 3)
        XCTAssertEqual(v.x, 1)
        XCTAssertEqual(v.y, 2)
        XCTAssertEqual(v.z, 3)
    }

    func testZeroVector() {
        let v = Vector3.zero
        XCTAssertEqual(v.x, 0)
        XCTAssertEqual(v.y, 0)
        XCTAssertEqual(v.z, 0)
    }

    // MARK: - Arithmetic Tests

    func testAddition() {
        let v1 = Vector3(1, 2, 3)
        let v2 = Vector3(4, 5, 6)
        let result = v1 + v2
        XCTAssertEqual(result, Vector3(5, 7, 9))
    }

    func testSubtraction() {
        let v1 = Vector3(10, 8, 6)
        let v2 = Vector3(1, 2, 3)
        let result = v1 - v2
        XCTAssertEqual(result, Vector3(9, 6, 3))
    }

    func testScalarMultiplication() {
        let v = Vector3(1, 2, 3)
        let result = v * 2.0
        XCTAssertEqual(result, Vector3(2, 4, 6))
    }

    func testScalarMultiplicationReversed() {
        let v = Vector3(1, 2, 3)
        let result = 2.0 * v
        XCTAssertEqual(result, Vector3(2, 4, 6))
    }

    func testScalarDivision() {
        let v = Vector3(4, 6, 8)
        let result = v / 2.0
        XCTAssertEqual(result, Vector3(2, 3, 4))
    }

    func testNegation() {
        let v = Vector3(1, -2, 3)
        let result = -v
        XCTAssertEqual(result, Vector3(-1, 2, -3))
    }

    // MARK: - Dot Product Tests

    func testDotProduct() {
        let v1 = Vector3(1, 0, 0)
        let v2 = Vector3(0, 1, 0)
        XCTAssertEqual(v1.dot(v2), 0.0)

        let v3 = Vector3(1, 2, 3)
        let v4 = Vector3(4, 5, 6)
        XCTAssertEqual(v3.dot(v4), 32.0) // 1*4 + 2*5 + 3*6 = 32
    }

    // MARK: - Cross Product Tests

    func testCrossProduct() {
        let v1 = Vector3(1, 0, 0)
        let v2 = Vector3(0, 1, 0)
        let result = v1.cross(v2)
        XCTAssertEqual(result, Vector3(0, 0, 1))
    }

    func testCrossProductAnticommutative() {
        let v1 = Vector3(1, 2, 3)
        let v2 = Vector3(4, 5, 6)
        let cross1 = v1.cross(v2)
        let cross2 = v2.cross(v1)
        XCTAssertEqual(cross1, -cross2)
    }

    // MARK: - Length Tests

    func testLength() {
        let v = Vector3(3, 4, 0)
        XCTAssertEqual(v.length, 5.0, accuracy: 1e-10)
    }

    func testLengthSquared() {
        let v = Vector3(3, 4, 0)
        XCTAssertEqual(v.lengthSquared, 25.0)
    }

    // MARK: - Normalization Tests

    func testNormalize() {
        let v = Vector3(3, 4, 0)
        let normalized = v.normalized()
        XCTAssertEqual(normalized.length, 1.0, accuracy: 1e-10)
    }

    func testNormalizePreservesDirection() {
        for _ in 0..<100 {
            let v = Vector3(
                Double.random(in: -100...100),
                Double.random(in: -100...100),
                Double.random(in: -100...100)
            )
            guard v.length > 0 else { continue }

            let normalized = v.normalized()
            XCTAssertEqual(normalized.length, 1.0, accuracy: 1e-10)

            // Direction should be preserved (dot product positive)
            let dotProduct = v.dot(normalized)
            XCTAssertGreaterThan(dotProduct, 0)
        }
    }

    func testNormalizeZeroVector() {
        let v = Vector3.zero
        let normalized = v.normalized()
        XCTAssertEqual(normalized, Vector3.zero)
    }

    // MARK: - Distance Tests

    func testDistance() {
        let v1 = Vector3(0, 0, 0)
        let v2 = Vector3(3, 4, 0)
        XCTAssertEqual(v1.distance(to: v2), 5.0, accuracy: 1e-10)
    }

    func testDistanceSquared() {
        let v1 = Vector3(0, 0, 0)
        let v2 = Vector3(3, 4, 0)
        XCTAssertEqual(v1.distanceSquared(to: v2), 25.0)
    }

    // MARK: - Min/Max Tests

    func testMin() {
        let v1 = Vector3(1, 5, 3)
        let v2 = Vector3(2, 3, 4)
        let result = v1.min(v2)
        XCTAssertEqual(result, Vector3(1, 3, 3))
    }

    func testMax() {
        let v1 = Vector3(1, 5, 3)
        let v2 = Vector3(2, 3, 4)
        let result = v1.max(v2)
        XCTAssertEqual(result, Vector3(2, 5, 4))
    }

    // MARK: - Equality Tests

    func testEquality() {
        let v1 = Vector3(1, 2, 3)
        let v2 = Vector3(1, 2, 3)
        let v3 = Vector3(1, 2, 4)

        XCTAssertEqual(v1, v2)
        XCTAssertNotEqual(v1, v3)
    }

    func testApproximateEquality() {
        let v1 = Vector3(1.0, 2.0, 3.0)
        let v2 = Vector3(1.0000000001, 2.0, 3.0)

        XCTAssertTrue(v1.isApproximatelyEqual(to: v2, tolerance: 1e-9))
        XCTAssertFalse(v1.isApproximatelyEqual(to: v2, tolerance: 1e-11))
    }

    // MARK: - Constants Tests

    func testConstants() {
        XCTAssertEqual(Vector3.zero, Vector3(0, 0, 0))
        XCTAssertEqual(Vector3.one, Vector3(1, 1, 1))
        XCTAssertEqual(Vector3.unitX, Vector3(1, 0, 0))
        XCTAssertEqual(Vector3.unitY, Vector3(0, 1, 0))
        XCTAssertEqual(Vector3.unitZ, Vector3(0, 0, 1))
    }

    // MARK: - Codable Tests

    func testCodable() throws {
        let original = Vector3(1.5, 2.5, 3.5)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Vector3.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - Conversion Tests

    func testFloat3Conversion() {
        let v = Vector3(1.5, 2.5, 3.5)
        let f3 = v.float3

        XCTAssertEqual(f3.x, Float(1.5))
        XCTAssertEqual(f3.y, Float(2.5))
        XCTAssertEqual(f3.z, Float(3.5))
    }
}
