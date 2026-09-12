import XCTest
@testable import GoSTL

/// Colours in a 3MF, the way the spec puts them there.
///
/// A `<basematerials>` or an `<m:colorgroup>` is a list of colours; an object
/// points at one with `pid` and `pindex`, and a triangle overrides that with
/// `pid` and `p1`. Cadova writes exactly this, and the viewer showed all of
/// it white: the only colours it knew were Bambu's extruder numbers out of
/// `model_settings.config`.
final class ThreeMFColorTests: XCTestCase {
    private let red = TriangleColor(hex: "#FF0000")!
    private let blue = TriangleColor(hex: "#0000FF")!
    private let green = TriangleColor(hex: "#00FF00")!

    // MARK: - The colour string

    func testHexColorsAsTheSpecWritesThem() {
        XCTAssertEqual(TriangleColor(hex: "#FF8000"), TriangleColor(1, 128.0 / 255, 0, 1))
        XCTAssertEqual(TriangleColor(hex: "#ff8000"), TriangleColor(hex: "#FF8000"))
        XCTAssertEqual(TriangleColor(hex: "ff8000"), TriangleColor(hex: "#FF8000"))
        XCTAssertEqual(TriangleColor(hex: "#FF800080"), TriangleColor(1, 128.0 / 255, 0, 128.0 / 255))
        XCTAssertNil(TriangleColor(hex: "#FF80"))
        XCTAssertNil(TriangleColor(hex: "#GG0000"))
    }

    // MARK: - Where a colour comes from

    /// A colour group after the object that uses it, which is Cadova's order
    /// and not the spec's: the references are only resolved once the whole
    /// document is read, so it makes no difference.
    func testTrianglesColouredThroughAColorGroupDeclaredAfterTheObject() throws {
        let model = try parse(model: """
            <resources>
              <object id="1" type="model">
                <mesh>
                  \(square)
                  <triangles>
                    <triangle v1="0" v2="1" v3="2" pid="2" p1="0"/>
                    <triangle v1="0" v2="2" v3="3" pid="2" p1="1"/>
                  </triangles>
                </mesh>
              </object>
              <m:colorgroup id="2">
                <m:color color="#FF0000"/>
                <m:color color="#0000FF"/>
              </m:colorgroup>
            </resources>
            <build><item objectid="1"/></build>
            """)
        XCTAssertEqual(model.triangles.map(\.color), [red, blue])
    }

    /// The object's `pid`/`pindex` is the default for every triangle that
    /// says nothing itself, out of the core spec's `<basematerials>`.
    func testAnObjectsOwnMaterialColoursItsTriangles() throws {
        let model = try parse(model: """
            <resources>
              <basematerials id="5">
                <base name="Green" displaycolor="#00FF00"/>
              </basematerials>
              <object id="1" type="model" pid="5" pindex="0">
                <mesh>
                  \(square)
                  <triangles>
                    <triangle v1="0" v2="1" v3="2"/>
                    <triangle v1="0" v2="2" v3="3"/>
                  </triangles>
                </mesh>
              </object>
            </resources>
            <build><item objectid="1"/></build>
            """)
        XCTAssertEqual(model.triangles.map(\.color), [green, green])
    }

    /// `p1` on its own takes the object's group: the spec lets a triangle
    /// leave `pid` out when it means the object's.
    func testATriangleIndexWithoutAGroupUsesTheObjects() throws {
        let model = try parse(model: """
            <resources>
              <m:colorgroup id="2">
                <m:color color="#FF0000"/>
                <m:color color="#0000FF"/>
              </m:colorgroup>
              <object id="1" type="model" pid="2" pindex="0">
                <mesh>
                  \(square)
                  <triangles>
                    <triangle v1="0" v2="1" v3="2"/>
                    <triangle v1="0" v2="2" v3="3" p1="1"/>
                  </triangles>
                </mesh>
              </object>
            </resources>
            <build><item objectid="1"/></build>
            """)
        XCTAssertEqual(model.triangles.map(\.color), [red, blue])
    }

    /// A component without a colour of its own takes its parent's.
    func testAComponentInheritsItsParentsColour() throws {
        let model = try parse(model: """
            <resources>
              <m:colorgroup id="2">
                <m:color color="#0000FF"/>
              </m:colorgroup>
              <object id="1" type="model">
                <mesh>
                  \(square)
                  <triangles>
                    <triangle v1="0" v2="1" v3="2"/>
                  </triangles>
                </mesh>
              </object>
              <object id="3" type="model" pid="2" pindex="0">
                <components>
                  <component objectid="1" transform="1 0 0 0 1 0 0 0 1 10 0 0"/>
                </components>
              </object>
            </resources>
            <build><item objectid="3"/></build>
            """)
        XCTAssertEqual(model.triangles.map(\.color), [blue])
    }

    /// A model without any material is what it was before: no colour, and
    /// the renderer's default takes over.
    func testAModelWithoutMaterialsHasNoColour() throws {
        let model = try parse(model: """
            <resources>
              <object id="1" type="model">
                <mesh>
                  \(square)
                  <triangles>
                    <triangle v1="0" v2="1" v3="2"/>
                  </triangles>
                </mesh>
              </object>
            </resources>
            <build><item objectid="1"/></build>
            """)
        XCTAssertEqual(model.triangles.map(\.color), [nil])
    }

    /// The production extension puts each part in a model file of its own,
    /// named by `p:path` on the build item, with its own colour groups. The
    /// group ids repeat across files and mean nothing outside their own.
    func testABuildItemInAnotherModelFileBringsItsOwnColours() throws {
        let part = """
            <?xml version="1.0"?>
            <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:m="http://schemas.microsoft.com/3dmanufacturing/material/2015/02">
              <resources>
                <object id="7" type="model" name="part" pid="2" pindex="0">
                  <mesh>
                    \(square)
                    <triangles>
                      <triangle v1="0" v2="1" v3="2"/>
                    </triangles>
                  </mesh>
                </object>
                <m:colorgroup id="2">
                  <m:color color="#00FF00"/>
                </m:colorgroup>
              </resources>
            </model>
            """
        let model = try parse(model: """
            <resources>
              <m:colorgroup id="2">
                <m:color color="#FF0000"/>
              </m:colorgroup>
            </resources>
            <build>
              <item objectid="7" p:path="/3D/part.model" transform="1 0 0 0 1 0 0 0 1 0 5 0"/>
            </build>
            """, extraFiles: ["3D/part.model": part])
        XCTAssertEqual(model.triangles.map(\.color), [green])
    }

    // MARK: - The files Cadova writes

    /// One object, four colours on its triangles, and the colour group
    /// declared after the object. The counts are what the file says: each
    /// triangle's `p1` into the group.
    func testCadovasSingleObjectAssembly() throws {
        let model = try ThreeMFParser.parse(url: example("zusammenbau.3mf"))
        XCTAssertEqual(model.triangleCount, 2126)
        XCTAssertEqual(colourCounts(model), ["#3b7dd8": 758, "#d9d4c7": 228, "#5aa469": 262, "#e07a2f": 878])
    }

    /// The same assembly as four parts, each in its own model file with the
    /// colour on the object and none on the triangles. The parts are no
    /// longer unioned into each other, so the wall is a plain box again.
    func testCadovasAssemblyInParts() throws {
        let model = try ThreeMFParser.parse(url: example("zusammenbau-teile.3mf"))
        XCTAssertEqual(model.triangleCount, 2130)
        XCTAssertEqual(colourCounts(model), ["#3b7dd8": 668, "#d9d4c7": 12, "#5aa469": 348, "#e07a2f": 1102])
    }

    // MARK: - Helpers

    private let square = """
        <vertices>
          <vertex x="0" y="0" z="0"/>
          <vertex x="1" y="0" z="0"/>
          <vertex x="1" y="1" z="0"/>
          <vertex x="0" y="1" z="0"/>
        </vertices>
        """

    /// A 3MF around `body`, which is what goes between `<model>` and
    /// `</model>`, with the namespaces Cadova declares.
    private func parse(model body: String, extraFiles: [String: String] = [:]) throws -> STLModel {
        let document = """
            <?xml version="1.0"?>
            <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:m="http://schemas.microsoft.com/3dmanufacturing/material/2015/02" xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06">
            \(body)
            </model>
            """
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
            ("3D/3dmodel.model", Data(document.utf8)),
        ]
        for (name, content) in extraFiles.sorted(by: { $0.key < $1.key }) {
            files.append((name, Data(content.utf8)))
        }
        return try ThreeMFParser.parse(data: StoredZip.archive(files), name: "test")
    }

    private func example(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // GoSTLTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // GoSTL-Swift
            .deletingLastPathComponent()  // repository
            .appendingPathComponent("examples/cadova/\(name)")
    }

    /// How many triangles wear each colour, keyed by the hex the file wrote.
    private func colourCounts(_ model: STLModel) -> [String: Int] {
        var counts: [String: Int] = [:]
        for triangle in model.triangles {
            counts[hex(triangle.color), default: 0] += 1
        }
        return counts
    }

    private func hex(_ color: TriangleColor?) -> String {
        guard let color else { return "none" }
        let channels = [color.r, color.g, color.b].map { String(format: "%02x", Int(($0 * 255).rounded())) }
        return "#" + channels.joined()
    }
}

/// A zip with every entry stored, which is all the parser's reader needs and
/// all a test needs to write.
enum StoredZip {
    static func archive(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        for (name, content) in files {
            let nameData = Data(name.utf8)
            let offset = UInt32(out.count)
            let crc = crc32(content)
            // Local file header
            out.append(le32(0x04034b50))
            out.append(le16(20)); out.append(le16(0)); out.append(le16(0))  // version, flags, method (stored)
            out.append(le16(0)); out.append(le16(0))  // time, date
            out.append(le32(crc)); out.append(le32(UInt32(content.count))); out.append(le32(UInt32(content.count)))
            out.append(le16(UInt16(nameData.count))); out.append(le16(0))
            out.append(nameData)
            out.append(content)
            // Central directory entry
            central.append(le32(0x02014b50))
            central.append(le16(20)); central.append(le16(20)); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0))
            central.append(le32(crc)); central.append(le32(UInt32(content.count))); central.append(le32(UInt32(content.count)))
            central.append(le16(UInt16(nameData.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0))
            central.append(le32(offset))
            central.append(nameData)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        // End of central directory
        out.append(le32(0x06054b50))
        out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(files.count))); out.append(le16(UInt16(files.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(centralOffset))
        out.append(le16(0))
        return out
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB88320 : 0)
            }
        }
        return ~crc
    }
}
