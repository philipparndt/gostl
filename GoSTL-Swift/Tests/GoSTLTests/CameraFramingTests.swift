import XCTest
import simd
@testable import GoSTL

/// The framed model has to be inside the viewport, whatever shape the pane is.
///
/// Checked by projecting the bounding box's corners the way the renderer does,
/// so the test fails for the same reason the picture looks wrong.
final class CameraFramingTests: XCTestCase {
	/// Corners in normalised device coordinates: inside is -1...1 both ways.
	private func projectedCorners(_ bbox: BoundingBox, camera: Camera, aspect: Double) -> [SIMD2<Float>] {
		let matrix = camera.projectionMatrix(aspect: Float(aspect)) * camera.viewMatrix()
		var corners: [SIMD2<Float>] = []
		for x in [bbox.min.x, bbox.max.x] {
			for y in [bbox.min.y, bbox.max.y] {
				for z in [bbox.min.z, bbox.max.z] {
					let clip = matrix * SIMD4<Float>(Float(x), Float(y), Float(z), 1)
					guard clip.w > 0 else { continue }
					corners.append(SIMD2(clip.x / clip.w, clip.y / clip.w))
				}
			}
		}
		return corners
	}

	private func assertFits(
		_ bbox: BoundingBox, aspect: Double, angleX: Double, angleY: Double,
		file: StaticString = #filePath, line: UInt = #line
	) {
		let camera = Camera()
		camera.angleX = angleX
		camera.angleY = angleY
		camera.frameBoundingBox(bbox, aspect: aspect)

		for corner in projectedCorners(bbox, camera: camera, aspect: aspect) {
			XCTAssertLessThanOrEqual(abs(corner.x), 1.0, "off the sides at aspect \(aspect)", file: file, line: line)
			XCTAssertLessThanOrEqual(abs(corner.y), 1.0, "off the top or bottom at aspect \(aspect)", file: file, line: line)
		}
	}

	/// A wide flat plate, which is what a printable part usually is.
	private let plate = BoundingBox(
		min: Vector3(-60, -5, -25),
		max: Vector3(60, 5, 25)
	)

	func testFitsInASquarePane() {
		assertFits(plate, aspect: 1, angleX: 0.5, angleY: 0.6)
	}

	func testFitsInAWidePane() {
		assertFits(plate, aspect: 2.4, angleX: 0.5, angleY: 0.6)
	}

	/// The case that started this: the preview dragged down to a narrow column.
	func testFitsInANarrowPane() {
		for aspect in [0.8, 0.55, 0.3, 0.15] {
			assertFits(plate, aspect: aspect, angleX: 0.5, angleY: 0.6)
		}
	}

	/// Rotation must not push it out either — the fit is meant to hold at any angle.
	func testFitsAtEveryAngle() {
		for angleY in stride(from: 0.0, to: 6.2, by: 0.7) {
			assertFits(plate, aspect: 0.4, angleX: 0.6, angleY: angleY)
		}
	}

	/// Resizing after loading must re-fit rather than leave the model cropped.
	func testReframingANarrowedPaneKeepsItInside() {
		let camera = Camera()
		camera.angleX = 0.5
		camera.angleY = 0.6
		camera.frameBoundingBox(plate, aspect: 2.0)
		camera.reframe(aspect: 0.35)

		for corner in projectedCorners(plate, camera: camera, aspect: 0.35) {
			XCTAssertLessThanOrEqual(abs(corner.x), 1.0, "off the sides after reframing")
			XCTAssertLessThanOrEqual(abs(corner.y), 1.0, "off the top or bottom after reframing")
		}
	}

	/// A model loaded while the pane is already narrow, with no resize to follow.
	func testLoadingIntoAnAlreadyNarrowPaneFits() {
		let camera = Camera()
		camera.angleX = 0.5
		camera.angleY = 0.6
		// The renderer reports the viewport before anything is loaded.
		camera.reframe(aspect: 0.35)
		// The caller does not know the size, as both real call sites do not.
		camera.frameBoundingBox(plate)

		for corner in projectedCorners(plate, camera: camera, aspect: 0.35) {
			XCTAssertLessThanOrEqual(abs(corner.x), 1.0, "off the sides when loaded into a narrow pane")
			XCTAssertLessThanOrEqual(abs(corner.y), 1.0, "off the top or bottom when loaded into a narrow pane")
		}
	}
}
