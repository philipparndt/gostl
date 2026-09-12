import XCTest
import simd
@testable import GoSTL

/// The camera goes all the way round.
///
/// The pitch used to be clamped 0.1 rad short of straight up and straight
/// down, so a drag that wanted the underside of a model simply stopped at the
/// top view; the only way under was the Bottom preset.
final class CameraRotationTests: XCTestCase {
    /// Where `point` lands on a unit screen, for telling a smooth turn from a
    /// jump.
    private func screen(_ point: SIMD3<Float>, _ camera: Camera) -> SIMD2<Float> {
        let clip = camera.projectionMatrix(aspect: 1) * camera.viewMatrix() * SIMD4<Float>(point, 1)
        return SIMD2(clip.x / clip.w, clip.y / clip.w)
    }

    func testDraggingPastTheTopComesDownTheOtherSide() {
        let camera = Camera()
        camera.angleX = 1.4
        camera.angleY = 0

        camera.rotate(deltaX: 0.4, deltaY: 0)

        XCTAssertEqual(camera.angleX, 1.8, accuracy: 1e-9)
        // Still above the target, but on the far side of the pole.
        XCTAssertGreaterThan(camera.position.z, 0)
        XCTAssertLessThan(camera.position.y, 0)
        XCTAssertEqual(camera.up, SIMD3(0, 0, -1))
    }

    func testTheUndersideCanBeReachedByDragging() {
        let camera = Camera()
        camera.angleX = 0.3

        camera.rotate(deltaX: -2.0, deltaY: 0)

        XCTAssertLessThan(camera.position.z, 0)
    }

    /// The picture must not snap as the camera crosses the pole: a point off
    /// to the side moves a little per step, never across the screen.
    func testCrossingThePoleIsContinuousOnScreen() {
        let camera = Camera()
        camera.angleX = .pi / 2 - 0.05
        camera.angleY = 0.7
        camera.distance = 50
        let point = SIMD3<Float>(10, 4, 0)

        var previous = screen(point, camera)
        for _ in 0..<10 {
            camera.rotate(deltaX: 0.01, deltaY: 0)
            let now = screen(point, camera)
            XCTAssertLessThan(simd_distance(previous, now), 0.05, "jumped at pitch \(camera.angleX)")
            previous = now
        }
        XCTAssertGreaterThan(camera.angleX, .pi / 2)
    }

    func testThePitchStaysWithinOneTurn() {
        let camera = Camera()
        camera.angleX = 3.0
        camera.rotate(deltaX: 0.5, deltaY: 0)
        XCTAssertEqual(camera.angleX, 3.5 - 2 * .pi, accuracy: 1e-9)

        camera.angleX = -3.0
        camera.rotate(deltaX: -0.5, deltaY: 0)
        XCTAssertEqual(camera.angleX, -3.5 + 2 * .pi, accuracy: 1e-9)
    }

    /// Exactly at the pole Z is along the line of sight; the view matrix must
    /// still be a matrix.
    func testThePoleItselfIsNotDegenerate() {
        let camera = Camera()
        camera.angleX = .pi / 2
        camera.angleY = 0.3
        let view = camera.viewMatrix()
        for column in 0..<4 {
            for row in 0..<4 {
                XCTAssertFalse(view[column][row].isNaN, "NaN at \(column),\(row)")
            }
        }
    }
}
