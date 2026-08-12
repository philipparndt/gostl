import XCTest
@testable import GoSTL

/// What the viewer asks go3mf to do when somebody presses `o`.
///
/// The claim under test is a negative one, which is why it is worth a test at
/// all: the arguments must *not* contain `--open`. Pressing `o` used to open the
/// built `.3mf` twice — go3mf opened it because of `--open`, and then the viewer
/// opened it again on success, commented as a fallback — so the slicer was
/// handed the same file two times and showed it two times (0481). Both call
/// sites build their arguments here, so this one assertion covers both.
final class Go3mfArgumentsTests: XCTestCase {
    private let input = URL(fileURLWithPath: "/models/bracket.stl")
    private let output = URL(fileURLWithPath: "/models/bracket.3mf")

    func testTheArgumentsNeverAskGo3mfToOpenTheResult() {
        XCTAssertFalse(
            go3mfBuildArguments(input: input, output: output).contains("--open"),
            "the viewer opens the result itself; asking go3mf to as well opens it twice"
        )
    }

    func testTheArgumentsBuildTheOutputFromTheInput() {
        XCTAssertEqual(
            go3mfBuildArguments(input: input, output: output),
            ["build", "/models/bracket.stl", "-o", "/models/bracket.3mf"]
        )
    }
}
