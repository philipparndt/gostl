import XCTest
@testable import GoSTL

/// Showing a go3mf recipe must not write to the project the recipe lives in.
///
/// `go3mf build <recipe> -o <temp>` reads as if it decides where the result
/// goes. It does not: for a YAML recipe go3mf takes the name from the recipe's
/// own mandatory `output:` and writes it relative to its *working directory*,
/// then exits 0. Run in the recipe's own directory, as the viewer did, that
/// overwrote the project's `.3mf` under exactly the name the recipe names —
/// where a hand-made or hand-sliced file normally sits — and then the viewer
/// parsed a temporary file that had never been created (`NSCocoaErrorDomain
/// 260`).
///
/// So the working directory is what these tests are about. The last test runs
/// the real go3mf against a real recipe and checks the claim directly, by
/// checksumming the project directory either side of the build.
final class Go3mfRecipeTests: XCTestCase {

    // MARK: - What the recipe declares

    func testTheDeclaredOutputIsRead() {
        XCTAssertEqual(go3mfRecipeDeclaredOutput(inRecipe: "output: combined.3mf\n"), "combined.3mf")
    }

    func testTheDeclaredOutputSurvivesTheRestOfARealRecipe() {
        // The shape of ~/dev/3d/other/hubelino/adapter-set.yaml, which is the
        // recipe this was found on.
        let recipe = """
        # Adapter und Feder-Adapter zusammen auf eine Platte.
        #
        #   go3mf combine adapter-set.yaml

        output: adapter-set.3mf

        packing_distance: 10.0

        objects:
          - name: Adapter
            parts:
              - name: adapter
                file: ./adapter.scad
        """

        XCTAssertEqual(go3mfRecipeDeclaredOutput(inRecipe: recipe), "adapter-set.3mf")
    }

    func testAnInlineCommentIsNotPartOfTheName() {
        XCTAssertEqual(
            go3mfRecipeDeclaredOutput(inRecipe: "output: plate.3mf  # the whole set\n"),
            "plate.3mf"
        )
    }

    func testAQuotedNameKeepsWhatIsInsideTheQuotes() {
        XCTAssertEqual(
            go3mfRecipeDeclaredOutput(inRecipe: "output: \"my # plate.3mf\"\n"),
            "my # plate.3mf"
        )
        XCTAssertEqual(go3mfRecipeDeclaredOutput(inRecipe: "output: 'set.3mf'\n"), "set.3mf")
    }

    func testAnIndentedOutputIsNotTheRecipeSOutput() {
        // Only a top-level key is the one go3mf unmarshals. Something nested
        // under an object, or a part's own key, must not be mistaken for it.
        let recipe = """
        objects:
          - name: Adapter
            output: not-this.3mf
            parts:
              - file: ./adapter.scad
        """

        XCTAssertNil(go3mfRecipeDeclaredOutput(inRecipe: recipe))
    }

    func testARecipeWithNoOutputDeclaresNone() {
        XCTAssertNil(go3mfRecipeDeclaredOutput(inRecipe: "objects:\n  - name: Adapter\n"))
        XCTAssertNil(go3mfRecipeDeclaredOutput(inRecipe: "output:\n"))
        XCTAssertNil(go3mfRecipeDeclaredOutput(inRecipe: "output:   # nothing\n"))
    }

    // MARK: - Where that lands, and where it may not

    private let buildDirectory = URL(fileURLWithPath: "/tmp/gostl-go3mf-build-1", isDirectory: true)

    func testARelativeOutputLandsInsideTheBuildDirectory() {
        XCTAssertEqual(
            go3mfRecipeOutputURL(declared: "adapter-set.3mf", buildDirectory: buildDirectory)?.path,
            "/tmp/gostl-go3mf-build-1/adapter-set.3mf"
        )
        XCTAssertEqual(
            go3mfRecipeOutputURL(declared: "./out/set.3mf", buildDirectory: buildDirectory)?.path,
            "/tmp/gostl-go3mf-build-1/out/set.3mf"
        )
    }

    func testAnAbsoluteOutputIsRefused() {
        // The one case the working directory cannot contain: go3mf would write
        // it wherever the recipe says, which may be the project being viewed.
        XCTAssertNil(
            go3mfRecipeOutputURL(
                declared: "/Users/somebody/hubelino/adapter-set.3mf",
                buildDirectory: buildDirectory
            )
        )
    }

    func testAnOutputThatClimbsOutIsRefused() {
        XCTAssertNil(
            go3mfRecipeOutputURL(declared: "../../escaped.3mf", buildDirectory: buildDirectory)
        )
        XCTAssertNil(go3mfRecipeOutputURL(declared: ".", buildDirectory: buildDirectory))
    }

    func testASiblingWhoseNameStartsTheSameWayIsNotInside() {
        // "/tmp/gostl-go3mf-build-12/x.3mf" begins with the build directory's
        // path as a string and is not in it.
        XCTAssertNil(
            go3mfRecipeOutputURL(declared: "../gostl-go3mf-build-12/x.3mf", buildDirectory: buildDirectory)
        )
    }

    // MARK: - The arguments

    func testARecipeIsBuiltWithoutMinusO() {
        // The whole bug in one assertion: `-o` looked like it chose the output
        // and go3mf ignored it, so the viewer neither wrote where it thought
        // nor read what was written.
        let arguments = go3mfRecipeBuildArguments(recipe: URL(fileURLWithPath: "/p/adapter-set.yaml"))

        XCTAssertEqual(arguments, ["build", "/p/adapter-set.yaml"])
        XCTAssertFalse(arguments.contains("-o"), "go3mf ignores -o for a recipe")
        XCTAssertFalse(arguments.contains("--output"))
    }

    // MARK: - Cleaning up after a build

    func testTheBuildDirectoryGoesWithTheFileItBuilt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(Go3mfToolRenderer.buildDirectoryPrefix + UUID().uuidString)
        let nested = directory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let built = nested.appendingPathComponent("set.3mf")
        try Data("3mf".utf8).write(to: built)

        removeTemporaryBuildArtifact(at: built)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: directory.path),
            "a build directory of ours goes whole, even when the output sat in a subdirectory of it"
        )
    }

    func testADirectoryThatIsNotOursIsLeftAlone() throws {
        // The guard that makes a recursive delete safe to write at all: the
        // directory has to be a direct child of the temporary directory and
        // carry the prefix this program puts there.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("somebody-elses-work-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keep = directory.appendingPathComponent("keep.stl")
        let built = directory.appendingPathComponent("built.3mf")
        try Data("stl".utf8).write(to: keep)
        try Data("3mf".utf8).write(to: built)

        removeTemporaryBuildArtifact(at: built)

        XCTAssertFalse(FileManager.default.fileExists(atPath: built.path), "the file it was given goes")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: keep.path),
            "and nothing else does"
        )

        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Against the real go3mf

    /// The claim, checked end to end: building a recipe leaves the directory the
    /// recipe lives in byte for byte as it was.
    ///
    /// Runs the installed `go3mf`, and skips when there is none - the recipe is
    /// STL-only so no OpenSCAD is needed and the build takes milliseconds. The
    /// project it builds is a copy in a temporary directory, and it contains a
    /// `recipe.3mf` standing in for the hand-made file that used to be
    /// overwritten: the recipe declares that name, which is exactly how the
    /// collision happens.
    func testBuildingARecipeLeavesTheProjectDirectoryUntouched() throws {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/go3mf")
                || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/go3mf") else {
            throw XCTSkip("go3mf is not installed on this machine")
        }

        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("gostl-recipe-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        let part = project.appendingPathComponent("PartA_1.stl")
        try FileManager.default.copyItem(at: try exampleSTL(), to: part)

        let handMade = project.appendingPathComponent("recipe.3mf")
        try Data("a 3MF somebody made by hand".utf8).write(to: handMade)

        let recipe = project.appendingPathComponent("recipe.yaml")
        try """
        output: recipe.3mf

        objects:
          - name: Part
            parts:
              - name: a
                file: ./PartA_1.stl
        """.write(to: recipe, atomically: true, encoding: .utf8)

        let before = try contents(of: project)

        let built = try Go3mfToolRenderer().buildRecipe(recipe)

        XCTAssertTrue(FileManager.default.fileExists(atPath: built.path), "it built something")
        XCTAssertFalse(
            built.path.hasPrefix(project.path),
            "and built it outside the project: \(built.path)"
        )
        XCTAssertEqual(
            try contents(of: project), before,
            "every file in the recipe's own directory is byte for byte what it was"
        )

        removeTemporaryBuildArtifact(at: built)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: built.path),
            "and the temporary build leaves nothing behind"
        )
    }

    /// A recipe whose `output:` names a file outside the build is refused
    /// before go3mf runs, so nothing is written anywhere.
    func testARecipeThatNamesAnAbsoluteOutputBuildsNothing() throws {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/go3mf")
                || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/go3mf") else {
            throw XCTSkip("go3mf is not installed on this machine")
        }

        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("gostl-recipe-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        let part = project.appendingPathComponent("PartA_1.stl")
        try FileManager.default.copyItem(at: try exampleSTL(), to: part)

        let target = project.appendingPathComponent("absolute.3mf")
        let recipe = project.appendingPathComponent("recipe.yaml")
        try """
        output: \(target.path)

        objects:
          - name: Part
            parts:
              - name: a
                file: ./PartA_1.stl
        """.write(to: recipe, atomically: true, encoding: .utf8)

        let before = try contents(of: project)

        XCTAssertThrowsError(try Go3mfToolRenderer().buildRecipe(recipe)) { error in
            guard case Go3mfError.buildFailed(let message) = error else {
                return XCTFail("expected a build failure, got \(error)")
            }
            XCTAssertTrue(
                message.contains(target.path),
                "the message names the output it will not write: \(message)"
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: target.path),
            "the absolute output it declared was not written"
        )
        XCTAssertEqual(try contents(of: project), before)
    }

    // MARK: -

    private func exampleSTL() throws -> URL {
        let repository = URL(fileURLWithPath: #filePath)  // …/Tests/GoSTLTests/this
            .deletingLastPathComponent()                  // …/Tests/GoSTLTests
            .deletingLastPathComponent()                  // …/Tests
            .deletingLastPathComponent()                  // …/GoSTL-Swift
            .deletingLastPathComponent()                  // …/
        let stl = repository.appendingPathComponent("examples/simple-named/PartA_1.stl")
        guard FileManager.default.fileExists(atPath: stl.path) else {
            throw XCTSkip("example STL not found at \(stl.path)")
        }
        return stl
    }

    /// Every file in a directory and its bytes, which is the comparison the
    /// claim needs — a mtime would not notice a rewrite with the same length.
    private func contents(of directory: URL) throws -> [String: Data] {
        var contents: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            contents[name] = try Data(contentsOf: directory.appendingPathComponent(name))
        }
        return contents
    }
}
