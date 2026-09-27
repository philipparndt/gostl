import XCTest
@testable import GoSTL

/// Where the resource bundle is found, and that not finding it is survivable.
///
/// Abydos 0.23.1 put `GoSTL_GoSTL.bundle` in `Contents/Resources`, where an app's
/// resources go, and died on the first 3D view on every machine but the one that
/// built it: `Bundle.module` looked at the app root and at a `.build` path from
/// somebody else's disk, then called `fatalError`.
final class ResourceBundleTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResourceBundleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// A host app's layout: the bundle in `Contents/Resources`, nothing at the root.
    func testABundleInAHostsResourcesIsFound() throws {
        let app = scratch.appendingPathComponent("Host.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let bundle = resources.appendingPathComponent("\(ResourceBundle.name).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        let found = ResourceBundle.locate(in: [app, resources])
        XCTAssertEqual(found?.bundleURL.standardizedFileURL, bundle.standardizedFileURL)
    }

    /// Nowhere to be found is `nil`, which the renderer turns into a thrown error.
    func testNoBundleAnywhereIsNilNotACrash() {
        XCTAssertNil(ResourceBundle.locate(in: [scratch, URL(fileURLWithPath: "/nonexistent")]))
    }

    /// The bundle this build actually produced, reached without `Bundle.module`.
    func testTheShadersOfThisBuildAreFound() {
        XCTAssertNotNil(ResourceBundle.bundle)
        let metallib = ResourceBundle.url(forResource: "default", withExtension: "metallib")
        let source = ResourceBundle.url(forResource: "Shaders", withExtension: "metal")
        XCTAssertTrue(metallib != nil || source != nil)
    }

    /// The accessor is generated and so always available to whoever types it
    /// next; this is the rule, kept by a test.
    func testNoSourceReachesForBundleModule() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GoSTL", isDirectory: true)

        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let code = text.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            if code.contains(where: { $0.contains("Bundle.module") }) {
                offenders.append(url.lastPathComponent)
            }
        }
        XCTAssertTrue(offenders.isEmpty, "use ResourceBundle — Bundle.module aborts: \(offenders)")
    }
}
