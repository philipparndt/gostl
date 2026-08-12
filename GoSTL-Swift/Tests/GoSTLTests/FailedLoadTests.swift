import XCTest
@testable import GoSTL

/// What a file that will not load looks like.
///
/// It used to look like a success. A `.scad` with an unclosed bracket, or any
/// `.scad` at all on a machine with no OpenSCAD, put a correctly lit cube on the
/// build plate: the catch called `setupInitialState(loadTestCube: true)`, and
/// somebody who had not written the file had no way to tell that the shape on
/// screen was not the shape their code described (0484). The message above it
/// does not settle this — an embedded pane is captured through the Metal
/// snapshot provider, which sees the model and not the SwiftUI overlay — so the
/// shape is the only thing that says whether the load worked, and a shape that
/// is not the model is a lie.
///
/// The rule these tests hold to is that a failure must never be
/// indistinguishable from a success, for a file that does not compile and for a
/// tool that is not installed alike.
final class FailedLoadTests: XCTestCase {

    private let scad = URL(fileURLWithPath: "/project/broken.scad")

    private func stateShowingSomething() -> AppState {
        let state = AppState()
        // Something is on screen, as it would be for the second file opened in
        // a window, so that "nothing drawn" is a change this can observe.
        state.model = STLModel(triangles: [
            Triangle(v1: Vector3(0, 0, 0), v2: Vector3(1, 0, 0), v3: Vector3(0, 1, 0))
        ])
        state.modelInfo = ModelInfo(fileName: "something.stl", triangleCount: 1)
        return state
    }

    func testNothingIsDrawnForAFileThatWouldNotLoad() {
        let state = stateShowingSomething()

        state.showFailedLoad(of: scad, error: OpenSCADError.renderFailed("syntax error", messages: []))

        XCTAssertNil(state.model, "no shape at all, rather than one that is not the model")
        XCTAssertNil(state.meshData)
        XCTAssertEqual(state.modelInfo?.fileName, "broken.scad", "and the file named is the one asked for")
        XCTAssertEqual(state.modelInfo?.triangleCount, 0)
    }

    func testAMissingToolIsAFailureLikeAnyOther() {
        // The worse of the two cases: GoSTL has install instructions written
        // for this, and a cube was what somebody got instead of them.
        let state = stateShowingSomething()

        state.showFailedLoad(of: scad, error: OpenSCADError.openSCADNotFound)

        XCTAssertNil(state.model)
        XCTAssertTrue(state.loadError is OpenSCADError)
        XCTAssertNotNil(state.loadErrorID, "the error is kept, so clearing it later means something")
    }

    func testAFailureIsNotAnEmptyFile() {
        // A different and much less alarming thing: the file rendered, and
        // described no geometry. Saying that about a file that did not compile
        // would be its own lie.
        let state = stateShowingSomething()
        state.isEmptyFile = true

        state.showFailedLoad(of: scad, error: OpenSCADError.renderFailed("syntax error", messages: []))

        XCTAssertFalse(state.isEmptyFile)
    }

    func testTheFileIsRememberedSoThatFixingItIsNoticed() {
        // The overlay promises that "the file will auto-reload when the error is
        // fixed", and for a failed first load nothing was watching anything:
        // the source URL was only set on success. A reload that then succeeds is
        // also what takes the message away again.
        let state = AppState()

        state.showFailedLoad(of: scad, error: OpenSCADError.renderFailed("syntax error", messages: []))

        XCTAssertEqual(state.sourceFileURL, scad)
        XCTAssertTrue(state.isOpenSCAD, "remembered as the kind of file it is, so a reload takes the same route")
        XCTAssertFalse(state.isGo3mf)
    }

    func testARecipeThatWouldNotBuildIsRememberedAsARecipe() {
        let state = AppState()
        let recipe = URL(fileURLWithPath: "/project/adapter-set.yaml")

        state.showFailedLoad(of: recipe, error: Go3mfError.buildFailed("no such part"))

        XCTAssertEqual(state.sourceFileURL, recipe)
        XCTAssertTrue(state.isGo3mf)
        XCTAssertFalse(state.isOpenSCAD)
        XCTAssertNil(state.model)
    }

    func testTheRenderMessagesSurviveTheFailure() {
        let state = AppState()

        state.showFailedLoad(
            of: scad,
            error: OpenSCADError.renderFailed("nope", messages: ["ERROR: Parser error: syntax error"])
        )

        XCTAssertEqual(state.renderWarnings, ["ERROR: Parser error: syntax error"])
    }

    /// The regression itself, guarded where it happened.
    ///
    /// Reading the source in a test is unusual and is the only way to hold this
    /// one: what it forbids is a call, in a place no unit test reaches, whose
    /// effect is only visible by looking at a running window. The alternative is
    /// a comment saying "do not put the cube back", which is roughly what was
    /// there.
    func testTheFailurePathDoesNotFallBackToTheTestCube() throws {
        let source = URL(fileURLWithPath: #filePath)  // …/Tests/GoSTLTests/this
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()              // …/GoSTL-Swift
            .appendingPathComponent("GoSTL/App/ContentView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let cubeCalls = lines.enumerated()
            .filter { $0.element.contains("setupInitialState(loadTestCube: true)") }
            .map { $0.offset + 1 }

        XCTAssertEqual(
            cubeCalls.count, 1,
            """
            the test cube belongs to exactly one place - a window opened with no \
            file at all, which has nothing else to show. A second call site is \
            the bug: it was in the catch of a load that failed. Found at lines \
            \(cubeCalls).
            """
        )

        // And the one that remains is the empty-window path, not a failure path.
        if let line = cubeCalls.first {
            let context = lines[max(0, line - 12)..<min(lines.count, line)].joined(separator: "\n")
            XCTAssertFalse(
                context.contains("} catch {"),
                "the remaining test cube must not be a fallback from a load that threw"
            )
        }
    }
}
