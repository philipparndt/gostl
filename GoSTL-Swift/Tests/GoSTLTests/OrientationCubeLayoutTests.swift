import XCTest
@testable import GoSTL

/// The orientation cube has to stay inside the view it decorates.
final class OrientationCubeLayoutTests: XCTestCase {
	private func assertInside(_ size: CGSize, file: StaticString = #filePath, line: UInt = #line) {
		let layout = OrientationCubeLayout(viewSize: size)
		XCTAssertGreaterThanOrEqual(layout.originX, 0, "off the left edge at \(size)", file: file, line: line)
		XCTAssertGreaterThanOrEqual(layout.originY, 0, "off the top edge at \(size)", file: file, line: line)
		XCTAssertLessThanOrEqual(
			layout.originX + layout.size, Double(size.width),
			"off the right edge at \(size)", file: file, line: line
		)
		XCTAssertLessThanOrEqual(
			layout.originY + layout.size, Double(size.height),
			"off the bottom edge at \(size)", file: file, line: line
		)
	}

	func testStaysInsideAWindowSizedView() {
		assertInside(CGSize(width: 2560, height: 1600))
	}

	/// The case that started this: the preview as a narrow column beside source.
	func testStaysInsideANarrowPane() {
		for width in [900.0, 600.0, 400.0, 240.0, 120.0, 40.0] {
			assertInside(CGSize(width: width, height: 1500))
		}
	}

	func testStaysInsideAShortPane() {
		for height in [900.0, 600.0, 300.0, 100.0, 30.0] {
			assertInside(CGSize(width: 2000, height: height))
		}
	}

	/// A view that has not been laid out yet must not produce nonsense.
	func testAnEmptyViewDrawsNothing() {
		let layout = OrientationCubeLayout(viewSize: .zero)
		XCTAssertFalse(layout.isVisible)
		XCTAssertEqual(layout.size, 0)
	}

	/// It keeps its full size whenever the view is big enough for it.
	func testItReachesFullSizeInARoomyView() {
		let layout = OrientationCubeLayout(viewSize: CGSize(width: 2560, height: 1600))
		XCTAssertEqual(layout.size, OrientationCubeLayout.preferredSize, accuracy: 0.001)
		XCTAssertEqual(layout.originY, OrientationCubeLayout.preferredMargin, accuracy: 0.001)
	}

	/// Shrinking rather than overflowing is the whole point.
	func testItShrinksWithThePane() {
		let roomy = OrientationCubeLayout(viewSize: CGSize(width: 2000, height: 1600))
		let cramped = OrientationCubeLayout(viewSize: CGSize(width: 400, height: 1600))
		XCTAssertLessThan(cramped.size, roomy.size)
		XCTAssertGreaterThan(cramped.size, 0)
	}

	/// Hit-testing has to agree with where it was drawn, in AppKit's flipped Y.
	func testHitTestingMatchesTheDrawnCorner() {
		let viewSize = CGSize(width: 1000, height: 800)
		let layout = OrientationCubeLayout(viewSize: viewSize)
		let height = Double(viewSize.height)

		let middle = CGPoint(
			x: layout.originX + layout.size / 2,
			y: layout.bottomUpMinY(viewHeight: height) + layout.size / 2
		)
		XCTAssertTrue(layout.contains(middle, viewHeight: height))

		// Just outside each edge.
		XCTAssertFalse(layout.contains(CGPoint(x: layout.originX - 1, y: middle.y), viewHeight: height))
		XCTAssertFalse(layout.contains(CGPoint(x: layout.originX + layout.size + 1, y: middle.y), viewHeight: height))
		// Below the cube, which sits at the top of the view.
		XCTAssertFalse(layout.contains(
			CGPoint(x: middle.x, y: layout.bottomUpMinY(viewHeight: height) - 1), viewHeight: height
		))
	}

	/// The cube is at the top of the view, so its bottom edge is high up.
	func testItSitsAtTheTopRight() {
		let viewSize = CGSize(width: 1000, height: 800)
		let layout = OrientationCubeLayout(viewSize: viewSize)
		XCTAssertGreaterThan(layout.bottomUpMinY(viewHeight: 800), 400)
		XCTAssertGreaterThan(layout.originX, 500)
	}
}
