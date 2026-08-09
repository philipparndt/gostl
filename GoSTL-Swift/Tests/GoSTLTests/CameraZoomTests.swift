import XCTest
import simd
@testable import GoSTL

/// Zooming has to work at the scale the model is, not at the scale the limits
/// were written for: a dollhouse frames at a distance of about 2200, so a fixed
/// ceiling of 1000 sat inside it and scrolling out did nothing at all.
final class CameraZoomTests: XCTestCase {
    /// The dollhouse, in millimetres.
    private var largeModel: BoundingBox {
        BoundingBox(min: Vector3(-92, 0, 0), max: Vector3(891, 406, 1082))
    }

    private var smallPart: BoundingBox {
        BoundingBox(min: Vector3(0, 0, 0), max: Vector3(20, 20, 20))
    }

    func testZoomingOutMovesBackFromALargeModel() {
        let camera = Camera()
        camera.frameBoundingBox(largeModel, aspect: 1.55)
        let framed = camera.distance

        camera.zoom(delta: 10)

        XCTAssertGreaterThan(camera.distance, framed)
    }

    func testZoomingInApproachesALargeModel() {
        let camera = Camera()
        camera.frameBoundingBox(largeModel, aspect: 1.55)
        let framed = camera.distance

        camera.zoom(delta: -10)

        XCTAssertLessThan(camera.distance, framed)
        XCTAssertGreaterThan(camera.distance, 0)
    }

    /// A step covers the same fraction of the view whatever the model measures.
    func testAStepFeelsTheSameAtEitherScale() {
        let large = Camera()
        large.frameBoundingBox(largeModel, aspect: 1.55)
        let small = Camera()
        small.frameBoundingBox(smallPart, aspect: 1.55)

        let largeBefore = large.distance, smallBefore = small.distance
        large.zoom(delta: 5)
        small.zoom(delta: 5)

        XCTAssertEqual(large.distance / largeBefore, small.distance / smallBefore, accuracy: 1e-9)
    }

    /// Scrolling far enough stops, rather than sending the model out of sight.
    func testZoomingStaysWithinReachOfTheModel() {
        let camera = Camera()
        camera.frameBoundingBox(largeModel, aspect: 1.55)
        let framed = camera.distance

        for _ in 0..<500 { camera.zoom(delta: 10) }
        XCTAssertLessThanOrEqual(camera.distance, framed * 25)

        for _ in 0..<1000 { camera.zoom(delta: -10) }
        XCTAssertGreaterThan(camera.distance, 0)
        XCTAssertLessThan(camera.distance, framed)
    }
}
