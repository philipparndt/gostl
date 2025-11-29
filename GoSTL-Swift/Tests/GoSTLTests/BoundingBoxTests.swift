import XCTest
@testable import GoSTL

final class BoundingBoxTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitWithPoints() {
        let points = [
            Vector3(0, 0, 0),
            Vector3(10, 5, 3),
            Vector3(-2, 8, 1)
        ]
        let bbox = BoundingBox(points: points)

        XCTAssertEqual(bbox.min, Vector3(-2, 0, 0))
        XCTAssertEqual(bbox.max, Vector3(10, 8, 3))
    }

    func testInitWithSinglePoint() {
        let point = Vector3(5, 10, 15)
        let bbox = BoundingBox(point: point)

        XCTAssertEqual(bbox.min, point)
        XCTAssertEqual(bbox.max, point)
    }

    // MARK: - Extend Tests

    func testExtendWithPoint() {
        var bbox = BoundingBox(point: Vector3(0, 0, 0))

        bbox.extend(Vector3(10, 5, 3))
        XCTAssertEqual(bbox.min, Vector3(0, 0, 0))
        XCTAssertEqual(bbox.max, Vector3(10, 5, 3))

        bbox.extend(Vector3(-5, 2, 8))
        XCTAssertEqual(bbox.min, Vector3(-5, 0, 0))
        XCTAssertEqual(bbox.max, Vector3(10, 5, 8))
    }

    func testExtendWithBox() {
        var bbox1 = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(5, 5, 5))
        let bbox2 = BoundingBox(min: Vector3(3, 3, 3), max: Vector3(10, 10, 10))

        bbox1.extend(bbox2)

        XCTAssertEqual(bbox1.min, Vector3(0, 0, 0))
        XCTAssertEqual(bbox1.max, Vector3(10, 10, 10))
    }

    // MARK: - Size Tests

    func testSize() {
        let bbox = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(10, 5, 3))
        XCTAssertEqual(bbox.size, Vector3(10, 5, 3))
    }

    func testCenter() {
        let bbox = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(10, 10, 10))
        XCTAssertEqual(bbox.center, Vector3(5, 5, 5))
    }

    func testDiagonal() {
        let bbox = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(3, 4, 0))
        XCTAssertEqual(bbox.diagonal, 5.0, accuracy: 1e-10)
    }

    // MARK: - Volume Tests

    func testVolume() {
        let bbox = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(10, 10, 10))
        XCTAssertEqual(bbox.volume, 1000.0)
    }

    func testVolumeNonUniform() {
        let bbox = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(10, 5, 2))
        XCTAssertEqual(bbox.volume, 100.0)
    }

    // MARK: - Surface Area Tests

    func testSurfaceArea() {
        let bbox = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(10, 10, 10))
        XCTAssertEqual(bbox.surfaceArea, 600.0) // 2 * (10*10 + 10*10 + 10*10)
    }

    // MARK: - Contains Tests

    func testContains() {
        let bbox = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(10, 10, 10))

        XCTAssertTrue(bbox.contains(Vector3(5, 5, 5)))
        XCTAssertTrue(bbox.contains(Vector3(0, 0, 0))) // min boundary
        XCTAssertTrue(bbox.contains(Vector3(10, 10, 10))) // max boundary
        XCTAssertFalse(bbox.contains(Vector3(-1, 5, 5)))
        XCTAssertFalse(bbox.contains(Vector3(11, 5, 5)))
    }

    // MARK: - Intersects Tests

    func testIntersects() {
        let bbox1 = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(10, 10, 10))
        let bbox2 = BoundingBox(min: Vector3(5, 5, 5), max: Vector3(15, 15, 15))
        let bbox3 = BoundingBox(min: Vector3(20, 20, 20), max: Vector3(30, 30, 30))

        XCTAssertTrue(bbox1.intersects(bbox2))
        XCTAssertTrue(bbox2.intersects(bbox1))
        XCTAssertFalse(bbox1.intersects(bbox3))
        XCTAssertFalse(bbox3.intersects(bbox1))
    }

    // MARK: - Corners Tests

    func testCorners() {
        let bbox = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(1, 1, 1))
        let corners = bbox.corners

        XCTAssertEqual(corners.count, 8)
        XCTAssertTrue(corners.contains(Vector3(0, 0, 0)))
        XCTAssertTrue(corners.contains(Vector3(1, 1, 1)))
        XCTAssertTrue(corners.contains(Vector3(0, 1, 0)))
        XCTAssertTrue(corners.contains(Vector3(1, 0, 1)))
    }

    // MARK: - Equality Tests

    func testEquality() {
        let bbox1 = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(10, 10, 10))
        let bbox2 = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(10, 10, 10))
        let bbox3 = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(5, 5, 5))

        XCTAssertEqual(bbox1, bbox2)
        XCTAssertNotEqual(bbox1, bbox3)
    }

    // MARK: - Codable Tests

    func testCodable() throws {
        let original = BoundingBox(min: Vector3(1, 2, 3), max: Vector3(10, 20, 30))

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BoundingBox.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}
