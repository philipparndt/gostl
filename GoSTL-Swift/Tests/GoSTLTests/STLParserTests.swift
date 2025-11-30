import XCTest
@testable import GoSTL

final class STLParserTests: XCTestCase {

    // MARK: - ASCII Parser Tests

    func testParseASCIICube() throws {
        let asciiSTL = """
        solid cube
        facet normal 0 0 1
          outer loop
            vertex 0 0 1
            vertex 1 0 1
            vertex 1 1 1
          endloop
        endfacet
        facet normal 0 0 1
          outer loop
            vertex 0 0 1
            vertex 1 1 1
            vertex 0 1 1
          endloop
        endfacet
        endsolid cube
        """

        let data = asciiSTL.data(using: .ascii)!
        let model = try STLParser.parse(data: data, name: "cube")

        XCTAssertEqual(model.triangleCount, 2)
        XCTAssertEqual(model.name, "cube")

        // Check first triangle
        let t1 = model.triangles[0]
        XCTAssertEqual(t1.v1, Vector3(0, 0, 1))
        XCTAssertEqual(t1.v2, Vector3(1, 0, 1))
        XCTAssertEqual(t1.v3, Vector3(1, 1, 1))
        XCTAssertEqual(t1.normal, Vector3(0, 0, 1))
    }

    func testParseASCIISingleTriangle() throws {
        let asciiSTL = """
        solid triangle
        facet normal 0 0 1
          outer loop
            vertex 0 0 0
            vertex 1 0 0
            vertex 0 1 0
          endloop
        endfacet
        endsolid triangle
        """

        let data = asciiSTL.data(using: .ascii)!
        let model = try STLParser.parse(data: data)

        XCTAssertEqual(model.triangleCount, 1)

        let triangle = model.triangles[0]
        XCTAssertEqual(triangle.v1, Vector3(0, 0, 0))
        XCTAssertEqual(triangle.v2, Vector3(1, 0, 0))
        XCTAssertEqual(triangle.v3, Vector3(0, 1, 0))
    }

    func testParseASCIIWithNegativeCoordinates() throws {
        let asciiSTL = """
        solid negative
        facet normal -1 0 0
          outer loop
            vertex -5.5 -2.3 1.7
            vertex -3.2 4.1 -0.8
            vertex 1.9 -6.4 2.2
          endloop
        endfacet
        endsolid negative
        """

        let data = asciiSTL.data(using: .ascii)!
        let model = try STLParser.parse(data: data)

        XCTAssertEqual(model.triangleCount, 1)

        let triangle = model.triangles[0]
        XCTAssertEqual(triangle.v1.x, -5.5, accuracy: 1e-10)
        XCTAssertEqual(triangle.v2.y, 4.1, accuracy: 1e-10)
        XCTAssertEqual(triangle.v3.z, 2.2, accuracy: 1e-10)
    }

    // MARK: - Binary Parser Tests

    func testParseBinarySingleTriangle() throws {
        // Create minimal binary STL file
        var data = Data()

        // 80-byte header (zeros)
        data.append(Data(count: 80))

        // Triangle count (1)
        var triangleCount: UInt32 = 1
        data.append(Data(bytes: &triangleCount, count: 4))

        // Normal (0, 0, 1)
        var nx: Float = 0, ny: Float = 0, nz: Float = 1
        data.append(Data(bytes: &nx, count: 4))
        data.append(Data(bytes: &ny, count: 4))
        data.append(Data(bytes: &nz, count: 4))

        // Vertex 1 (0, 0, 0)
        var v1x: Float = 0, v1y: Float = 0, v1z: Float = 0
        data.append(Data(bytes: &v1x, count: 4))
        data.append(Data(bytes: &v1y, count: 4))
        data.append(Data(bytes: &v1z, count: 4))

        // Vertex 2 (1, 0, 0)
        var v2x: Float = 1, v2y: Float = 0, v2z: Float = 0
        data.append(Data(bytes: &v2x, count: 4))
        data.append(Data(bytes: &v2y, count: 4))
        data.append(Data(bytes: &v2z, count: 4))

        // Vertex 3 (0, 1, 0)
        var v3x: Float = 0, v3y: Float = 1, v3z: Float = 0
        data.append(Data(bytes: &v3x, count: 4))
        data.append(Data(bytes: &v3y, count: 4))
        data.append(Data(bytes: &v3z, count: 4))

        // Attribute byte count (0)
        var attributes: UInt16 = 0
        data.append(Data(bytes: &attributes, count: 2))

        let model = try STLParser.parse(data: data, name: "binary_test")

        XCTAssertEqual(model.triangleCount, 1)
        XCTAssertEqual(model.name, "binary_test")

        let triangle = model.triangles[0]
        XCTAssertEqual(triangle.v1, Vector3(0, 0, 0))
        XCTAssertEqual(triangle.v2, Vector3(1, 0, 0))
        XCTAssertEqual(triangle.v3, Vector3(0, 1, 0))
        XCTAssertEqual(triangle.normal, Vector3(0, 0, 1))
    }

    // MARK: - Format Detection Tests

    func testFormatDetectionASCII() {
        let asciiSTL = "solid test\nfacet normal 0 0 1\n"
        let data = asciiSTL.data(using: .ascii)!

        // Should detect as ASCII and parse without error
        XCTAssertNoThrow(try STLParser.parse(data: data))
    }

    func testFormatDetectionBinary() throws {
        // Create minimal binary STL
        var data = Data(count: 80) // Header

        var triangleCount: UInt32 = 0
        data.append(Data(bytes: &triangleCount, count: 4))

        // Should detect as binary
        let model = try STLParser.parse(data: data)
        XCTAssertEqual(model.triangleCount, 0)
    }

    // MARK: - Error Handling Tests

    func testFileTooSmall() {
        let tinyData = Data([1, 2, 3])

        XCTAssertThrowsError(try STLParser.parse(data: tinyData)) { error in
            XCTAssertTrue(error is STLError)
        }
    }

    func testInvalidASCIIFormat() {
        let invalidSTL = """
        solid test
        facet normal 0 0 1
          outer loop
            vertex INVALID DATA
          endloop
        endfacet
        endsolid test
        """

        let data = invalidSTL.data(using: .ascii)!

        XCTAssertThrowsError(try STLParser.parse(data: data))
    }

    func testBinaryInconsistentSize() {
        var data = Data(count: 80) // Header

        // Claim 10 triangles
        var triangleCount: UInt32 = 10
        data.append(Data(bytes: &triangleCount, count: 4))

        // But don't provide the data
        // Should throw inconsistent size error

        XCTAssertThrowsError(try STLParser.parse(data: data)) { error in
            if let stlError = error as? STLError {
                if case .inconsistentSize = stlError {
                    // Expected error
                } else {
                    XCTFail("Wrong error type: \(stlError)")
                }
            } else {
                XCTFail("Expected STLError")
            }
        }
    }
}
