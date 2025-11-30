import XCTest
@testable import GoSTL

final class TriangleTests: XCTestCase {

    // MARK: - Normal Calculation Tests

    func testNormalCalculation() {
        let triangle = Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(1, 0, 0),
            v3: Vector3(0, 1, 0)
        )
        let normal = triangle.normal

        // Normal should point in +Z direction
        XCTAssertEqual(normal.x, 0, accuracy: 1e-10)
        XCTAssertEqual(normal.y, 0, accuracy: 1e-10)
        XCTAssertEqual(normal.z, 1, accuracy: 1e-10)
    }

    func testNormalUpdate() {
        var triangle = Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(1, 0, 0),
            v3: Vector3(0, 1, 0)
        )

        // Modify a vertex
        triangle.v3 = Vector3(0, 0, 1)

        // Update normal
        triangle.updateNormal()

        // Normal should now point in -Y direction
        XCTAssertEqual(triangle.normal.x, 0, accuracy: 1e-10)
        XCTAssertEqual(triangle.normal.y, -1, accuracy: 1e-10)
        XCTAssertEqual(triangle.normal.z, 0, accuracy: 1e-10)
    }

    // MARK: - Area Tests

    func testArea() {
        // Right triangle with legs 3 and 4
        let triangle = Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(3, 0, 0),
            v3: Vector3(0, 4, 0)
        )
        XCTAssertEqual(triangle.area(), 6.0, accuracy: 1e-10) // 0.5 * 3 * 4 = 6
    }

    func testAreaEquilateralTriangle() {
        // Equilateral triangle with side length 2
        let h = sqrt(3.0) // height
        let triangle = Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(2, 0, 0),
            v3: Vector3(1, h, 0)
        )
        let expectedArea = sqrt(3.0) // For side length 2
        XCTAssertEqual(triangle.area(), expectedArea, accuracy: 1e-10)
    }

    // MARK: - Edge Length Tests

    func testEdgeLengths() {
        let triangle = Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(3, 0, 0),
            v3: Vector3(0, 4, 0)
        )
        let edges = triangle.edgeLengths()

        XCTAssertEqual(edges.0, 3.0, accuracy: 1e-10)
        XCTAssertEqual(edges.1, 5.0, accuracy: 1e-10) // hypotenuse
        XCTAssertEqual(edges.2, 4.0, accuracy: 1e-10)
    }

    func testPerimeter() {
        let triangle = Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(3, 0, 0),
            v3: Vector3(0, 4, 0)
        )
        XCTAssertEqual(triangle.perimeter(), 12.0, accuracy: 1e-10) // 3 + 4 + 5
    }

    // MARK: - Center Tests

    func testCenter() {
        let triangle = Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(3, 0, 0),
            v3: Vector3(0, 3, 0)
        )
        let center = triangle.center()
        XCTAssertEqual(center, Vector3(1, 1, 0))
    }

    // MARK: - Angles Tests

    func testAnglesRightTriangle() {
        let triangle = Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(1, 0, 0),
            v3: Vector3(0, 1, 0)
        )
        let angles = triangle.angles()

        // Should be a right triangle with angles 90°, 45°, 45°
        XCTAssertEqual(angles.0, .pi / 2, accuracy: 1e-6) // 90 degrees
        XCTAssertEqual(angles.1, .pi / 4, accuracy: 1e-6) // 45 degrees
        XCTAssertEqual(angles.2, .pi / 4, accuracy: 1e-6) // 45 degrees
    }

    // MARK: - Vertices Array Tests

    func testVerticesArray() {
        let v1 = Vector3(1, 2, 3)
        let v2 = Vector3(4, 5, 6)
        let v3 = Vector3(7, 8, 9)
        let triangle = Triangle(v1: v1, v2: v2, v3: v3)

        let vertices = triangle.vertices
        XCTAssertEqual(vertices.count, 3)
        XCTAssertEqual(vertices[0], v1)
        XCTAssertEqual(vertices[1], v2)
        XCTAssertEqual(vertices[2], v3)
    }

    // MARK: - Equality Tests

    func testEquality() {
        let t1 = Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(1, 0, 0),
            v3: Vector3(0, 1, 0)
        )
        let t2 = Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(1, 0, 0),
            v3: Vector3(0, 1, 0)
        )
        let t3 = Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(2, 0, 0),
            v3: Vector3(0, 1, 0)
        )

        XCTAssertEqual(t1, t2)
        XCTAssertNotEqual(t1, t3)
    }

    // MARK: - Codable Tests

    func testCodable() throws {
        let original = Triangle(
            v1: Vector3(1, 2, 3),
            v2: Vector3(4, 5, 6),
            v3: Vector3(7, 8, 9)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Triangle.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}
