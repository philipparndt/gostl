import XCTest
@testable import GoSTL

final class STLModelTests: XCTestCase {

    // MARK: - Helper

    func createTestCube() -> STLModel {
        // Create a complete unit cube (1x1x1) at origin
        var triangles: [Triangle] = []

        // Bottom face (z = 0) - 2 triangles (reversed for outward normal -Z)
        triangles.append(Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(1, 1, 0),
            v3: Vector3(1, 0, 0)
        ))
        triangles.append(Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(0, 1, 0),
            v3: Vector3(1, 1, 0)
        ))

        // Top face (z = 1) - 2 triangles (reversed winding for outward normal)
        triangles.append(Triangle(
            v1: Vector3(0, 0, 1),
            v2: Vector3(1, 0, 1),
            v3: Vector3(1, 1, 1)
        ))
        triangles.append(Triangle(
            v1: Vector3(0, 0, 1),
            v2: Vector3(1, 1, 1),
            v3: Vector3(0, 1, 1)
        ))

        // Front face (y = 0) - 2 triangles (reversed for outward normal -Y)
        triangles.append(Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(1, 0, 0),
            v3: Vector3(1, 0, 1)
        ))
        triangles.append(Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(1, 0, 1),
            v3: Vector3(0, 0, 1)
        ))

        // Back face (y = 1) - 2 triangles
        triangles.append(Triangle(
            v1: Vector3(0, 1, 0),
            v2: Vector3(1, 1, 1),
            v3: Vector3(1, 1, 0)
        ))
        triangles.append(Triangle(
            v1: Vector3(0, 1, 0),
            v2: Vector3(0, 1, 1),
            v3: Vector3(1, 1, 1)
        ))

        // Left face (x = 0) - 2 triangles (reversed winding)
        triangles.append(Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(0, 0, 1),
            v3: Vector3(0, 1, 1)
        ))
        triangles.append(Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(0, 1, 1),
            v3: Vector3(0, 1, 0)
        ))

        // Right face (x = 1) - 2 triangles
        triangles.append(Triangle(
            v1: Vector3(1, 0, 0),
            v2: Vector3(1, 1, 0),
            v3: Vector3(1, 1, 1)
        ))
        triangles.append(Triangle(
            v1: Vector3(1, 0, 0),
            v2: Vector3(1, 1, 1),
            v3: Vector3(1, 0, 1)
        ))

        return STLModel(triangles: triangles, name: "test_cube")
    }

    // MARK: - Bounding Box Tests

    func testBoundingBox() {
        let model = createTestCube()
        let bbox = model.boundingBox()

        XCTAssertEqual(bbox.min, Vector3(0, 0, 0))
        XCTAssertEqual(bbox.max, Vector3(1, 1, 1))
    }

    func testBoundingBoxEmptyModel() {
        let model = STLModel(triangles: [])
        let bbox = model.boundingBox()

        // Should return zero bounding box
        XCTAssertEqual(bbox.min, Vector3.zero)
        XCTAssertEqual(bbox.max, Vector3.zero)
    }

    // MARK: - Surface Area Tests

    func testSurfaceArea() {
        // Create a simple square (2 triangles)
        let triangles = [
            Triangle(
                v1: Vector3(0, 0, 0),
                v2: Vector3(1, 0, 0),
                v3: Vector3(1, 1, 0)
            ),
            Triangle(
                v1: Vector3(0, 0, 0),
                v2: Vector3(1, 1, 0),
                v3: Vector3(0, 1, 0)
            )
        ]

        let model = STLModel(triangles: triangles)
        let area = model.surfaceArea()

        // Two right triangles with legs 1, forming a square of area 1
        XCTAssertEqual(area, 1.0, accuracy: 1e-10)
    }

    // MARK: - Volume Tests

    func testVolumeUnitCube() {
        // Create a complete unit cube
        let model = createTestCube()
        let volume = model.volume()

        // Volume of unit cube should be 1.0
        XCTAssertEqual(volume, 1.0, accuracy: 0.01)
    }

    func testVolumeTetrahedron() {
        // Regular tetrahedron
        let h = sqrt(2.0 / 3.0)
        let triangles = [
            // Bottom face
            Triangle(
                v1: Vector3(0, 0, 0),
                v2: Vector3(1, 0, 0),
                v3: Vector3(0.5, sqrt(3.0) / 2.0, 0)
            ),
            // Three side faces
            Triangle(
                v1: Vector3(0, 0, 0),
                v2: Vector3(0.5, sqrt(3.0) / 6.0, h),
                v3: Vector3(1, 0, 0)
            ),
            Triangle(
                v1: Vector3(1, 0, 0),
                v2: Vector3(0.5, sqrt(3.0) / 6.0, h),
                v3: Vector3(0.5, sqrt(3.0) / 2.0, 0)
            ),
            Triangle(
                v1: Vector3(0.5, sqrt(3.0) / 2.0, 0),
                v2: Vector3(0.5, sqrt(3.0) / 6.0, h),
                v3: Vector3(0, 0, 0)
            ),
        ]

        let model = STLModel(triangles: triangles)
        let volume = model.volume()

        // Regular tetrahedron with edge 1 has volume = 1/(6√2) ≈ 0.118
        XCTAssertGreaterThan(volume, 0)
        XCTAssertLessThan(volume, 1)
    }

    // MARK: - Edge Statistics Tests

    func testEdgeStatistics() {
        let triangles = [
            Triangle(
                v1: Vector3(0, 0, 0),
                v2: Vector3(3, 0, 0),
                v3: Vector3(0, 4, 0)
            )
        ]

        let model = STLModel(triangles: triangles)
        let stats = model.edgeStatistics()

        XCTAssertEqual(stats.count, 3)
        XCTAssertEqual(stats.min, 3.0, accuracy: 1e-10)
        XCTAssertEqual(stats.max, 5.0, accuracy: 1e-10) // hypotenuse
    }

    // MARK: - PLA Weight Tests

    func testPLAWeight100Percent() {
        let model = createTestCube()
        let weight = model.calculatePLAWeight(infill: 1.0)

        // Weight should be positive
        XCTAssertGreaterThan(weight, 0)
    }

    func testPLAWeight15Percent() {
        let model = createTestCube()
        let weight100 = model.calculatePLAWeight(infill: 1.0)
        let weight15 = model.calculatePLAWeight(infill: 0.15)

        // 15% should be less than 100%
        XCTAssertLessThan(weight15, weight100)
        XCTAssertGreaterThan(weight15, 0)
    }

    // MARK: - Edge Extraction Tests

    func testExtractEdges() {
        let triangles = [
            Triangle(
                v1: Vector3(0, 0, 0),
                v2: Vector3(1, 0, 0),
                v3: Vector3(0, 1, 0)
            ),
            Triangle(
                v1: Vector3(0, 0, 0),
                v2: Vector3(0, 1, 0),
                v3: Vector3(0, 0, 1)
            )
        ]

        let model = STLModel(triangles: triangles)
        let edges = model.extractEdges()

        // Should have 5 unique edges (shared edge counted once)
        XCTAssertEqual(edges.count, 5)
    }

    func testEdgeDeduplication() {
        // Two triangles sharing an edge
        let triangles = [
            Triangle(
                v1: Vector3(0, 0, 0),
                v2: Vector3(1, 0, 0),
                v3: Vector3(0.5, 1, 0)
            ),
            Triangle(
                v1: Vector3(1, 0, 0),
                v2: Vector3(0, 0, 0),  // Same edge, reversed
                v3: Vector3(0.5, -1, 0)
            )
        ]

        let model = STLModel(triangles: triangles)
        let edges = model.extractEdges()

        // Should deduplicate the shared edge
        XCTAssertEqual(edges.count, 5)
    }

    // MARK: - Average Vertex Spacing Tests

    func testAverageVertexSpacing() {
        let triangles = [
            Triangle(
                v1: Vector3(0, 0, 0),
                v2: Vector3(1, 0, 0),
                v3: Vector3(0, 1, 0)
            )
        ]

        let model = STLModel(triangles: triangles)
        let avgSpacing = model.averageVertexSpacing()

        // Average of edges 1, 1, √2
        let expected = (1.0 + 1.0 + sqrt(2.0)) / 3.0
        XCTAssertEqual(avgSpacing, expected, accuracy: 1e-10)
    }

    // MARK: - Analysis Tests

    func testAnalyze() {
        let model = createTestCube()
        let analysis = model.analyze()

        XCTAssertEqual(analysis.triangleCount, model.triangleCount)
        XCTAssertGreaterThan(analysis.volume, 0)
        XCTAssertGreaterThan(analysis.surfaceArea, 0)
        XCTAssertGreaterThan(analysis.weightPLA100, 0)
        XCTAssertGreaterThan(analysis.weightPLA15, 0)
        XCTAssertLessThan(analysis.weightPLA15, analysis.weightPLA100)
    }
}
