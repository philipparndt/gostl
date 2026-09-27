import XCTest
@testable import GoSTL

/// Where the resource bundle is found, and that not finding it is not fatal.
///
/// `Bundle.module` looked beside the `.app` and in the build directory of
/// whoever compiled the host, and aborted otherwise — so an app embedding the
/// viewer died on every machine but its builder's the first time it showed a
/// model. These hold the layouts that have to work.
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

    private func makeBundle(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("\(ResourceBundle.name).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data().write(to: url.appendingPathComponent("Shaders.metal"))
        return url
    }

    /// Where a signed host app has to carry it: codesign will not seal
    /// anything in the bundle root.
    func testFindsTheBundleInAHostAppsResources() throws {
        let resources = scratch.appendingPathComponent("Host.app/Contents/Resources", isDirectory: true)
        let expected = try makeBundle(in: resources)
        let macOS = scratch.appendingPathComponent("Host.app/Contents/MacOS", isDirectory: true)

        let directories = [macOS, ResourceBundle.applicationResources(containing: macOS)].compactMap { $0 }
        let found = ResourceBundle.locate(in: directories)

        XCTAssertEqual(found?.bundleURL.standardizedFileURL, expected.standardizedFileURL)
        XCTAssertNotNil(found?.url(forResource: "Shaders", withExtension: "metal"))
    }

    /// A tool nested deeper in the app still reaches the app's resources.
    func testWalksUpFromANestedToolToTheApp() {
        let tool = scratch.appendingPathComponent("Host.app/Contents/Resources/bin", isDirectory: true)
        let resources = ResourceBundle.applicationResources(containing: tool)
        XCTAssertEqual(resources?.lastPathComponent, "Resources")
        XCTAssertEqual(resources?.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent, "Host.app")
    }

    func testAPathOutsideAnyAppHasNoAppResources() {
        XCTAssertNil(ResourceBundle.applicationResources(containing: scratch))
    }

    /// The case that used to abort: nowhere to be found is `nil`, not a crash.
    func testNoBundleAnywhereIsNilRatherThanAnAbort() {
        XCTAssertNil(ResourceBundle.locate(in: [scratch, scratch.appendingPathComponent("missing")]))
    }

    /// The first directory that has one wins, so an override is honoured.
    func testTheFirstDirectoryThatHoldsItWins() throws {
        let first = scratch.appendingPathComponent("first", isDirectory: true)
        let second = scratch.appendingPathComponent("second", isDirectory: true)
        _ = try makeBundle(in: second)
        let expected = try makeBundle(in: first)

        let found = ResourceBundle.locate(in: [scratch, first, second])
        XCTAssertEqual(found?.bundleURL.standardizedFileURL, expected.standardizedFileURL)
    }

    /// Under `swift test` the real bundle sits beside the test bundle.
    func testTheRealBundleIsFoundUnderTest() {
        XCTAssertNotNil(ResourceBundle.bundle)
        XCTAssertNotNil(ResourceBundle.url(forResource: "Shaders", withExtension: "metal")
            ?? ResourceBundle.url(forResource: "default", withExtension: "metallib"))
    }
}
