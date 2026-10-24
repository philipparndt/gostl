import XCTest
@testable import GoSTL

/// Components that never end.
///
/// Abydos 0.23.7 died opening a 3MF with eleven thousand frames of
/// `collectTriangles` on the stack: a component named an external model that
/// did not load, the lookup fell back to the main model's object of the same
/// id, and that was the parent. A file that is a real cycle — which the spec
/// forbids and a broken exporter can still write — went the same way.
final class ThreeMFComponentTests: XCTestCase {
    private let triangle = """
        <mesh>
          <vertices>
            <vertex x="0" y="0" z="0"/>
            <vertex x="1" y="0" z="0"/>
            <vertex x="0" y="1" z="0"/>
          </vertices>
          <triangles><triangle v1="0" v2="1" v3="2"/></triangles>
        </mesh>
        """

    /// Bambu's shape: object 1 in the main model is a component pointing at
    /// object 1 in `3D/Objects/object_1.model`. Without that file it names
    /// nothing, and the rest of the plate is still read.
    func testAComponentInAModelFileThatIsNotThereNamesNothing() throws {
        let model = try parse(model: """
            <resources>
              <object id="1" type="model">
                <components><component p:path="/3D/Objects/object_1.model" objectid="1"/></components>
              </object>
              <object id="2" type="model">\(triangle)</object>
            </resources>
            <build><item objectid="1"/><item objectid="2"/></build>
            """)
        XCTAssertEqual(model.triangles.count, 1)
    }

    /// The same component with its file present is the file's object.
    func testAComponentInAnotherModelFileIsThatFilesObject() throws {
        let model = try parse(model: """
            <resources>
              <object id="1" type="model">
                <components><component p:path="/3D/Objects/object_1.model" objectid="1"/></components>
              </object>
            </resources>
            <build><item objectid="1"/></build>
            """, extraFiles: ["3D/Objects/object_1.model": document("""
            <resources><object id="1" type="model">\(triangle)</object></resources>
            """)])
        XCTAssertEqual(model.triangles.count, 1)
    }

    func testAnObjectThatContainsItselfIsDrawnOnce() throws {
        let model = try parse(model: """
            <resources>
              <object id="1" type="model">
                \(triangle)
                <components><component objectid="1"/></components>
              </object>
            </resources>
            <build><item objectid="1"/></build>
            """)
        XCTAssertEqual(model.triangles.count, 1)
    }

    /// A cycle is cut where it closes, so each object on it is drawn once.
    func testTwoObjectsThatContainEachOtherAreEachDrawnOnce() throws {
        let model = try parse(model: """
            <resources>
              <object id="1" type="model">
                \(triangle)
                <components><component objectid="2"/></components>
              </object>
              <object id="2" type="model">
                \(triangle)
                <components><component objectid="1"/></components>
              </object>
            </resources>
            <build><item objectid="1"/></build>
            """)
        XCTAssertEqual(model.triangles.count, 2)
    }

    /// The same object used twice side by side is not a cycle.
    func testAnObjectUsedTwiceIsDrawnTwice() throws {
        let model = try parse(model: """
            <resources>
              <object id="1" type="model">\(triangle)</object>
              <object id="2" type="model">
                <components>
                  <component objectid="1"/>
                  <component objectid="1" transform="1 0 0 0 1 0 0 0 1 5 0 0"/>
                </components>
              </object>
            </resources>
            <build><item objectid="2"/></build>
            """)
        XCTAssertEqual(model.triangles.count, 2)
    }

    // MARK: - Helpers

    private func document(_ body: String) -> String {
        """
        <?xml version="1.0"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06">
        \(body)
        </model>
        """
    }

    private func parse(model body: String, extraFiles: [String: String] = [:]) throws -> STLModel {
        var files: [(String, Data)] = [
            ("[Content_Types].xml", Data("""
                <?xml version="1.0"?>
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
                  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
                  <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
                </Types>
                """.utf8)),
            ("_rels/.rels", Data("""
                <?xml version="1.0"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                  <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
                </Relationships>
                """.utf8)),
            ("3D/3dmodel.model", Data(document(body).utf8)),
        ]
        for (name, content) in extraFiles.sorted(by: { $0.key < $1.key }) {
            files.append((name, Data(content.utf8)))
        }
        return try ThreeMFParser.parse(data: StoredZip.archive(files), name: "test")
    }
}
