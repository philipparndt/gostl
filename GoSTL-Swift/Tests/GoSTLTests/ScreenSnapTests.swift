import XCTest
import simd
@testable import GoSTL

/// Snapping is judged on screen, so the same click lands on a corner whether
/// the model is a 20 mm bracket or a 1.5 m dollhouse.
///
/// The threshold used to be a fixed 2 mm, which on a large model comes to a
/// couple of pixels: clicks fell just short of the corner and a 400 mm edge
/// measured 398.81.
final class ScreenSnapTests: XCTestCase {
    private let viewSize = CGSize(width: 1400, height: 900)

    /// A wall-sized triangle lying in the z = 0 plane, corner at the origin.
    private let wall = STLModel(triangles: [
        Triangle(
            v1: Vector3(0, 0, 0),
            v2: Vector3(400, 0, 0),
            v3: Vector3(0, 400, 0),
            normal: Vector3(0, 0, 1)
        )
    ], name: "wall")

    /// A camera looking at the wall from `height`, at the sort of oblique angle
    /// the app opens with.
    private func camera(height: Double) -> Camera {
        let camera = Camera()
        camera.target = SIMD3(100, 100, 0)
        camera.distance = height
        camera.angleX = 0.6
        camera.angleY = .pi + 0.5
        return camera
    }

    /// Where a world point lands on screen, in the coordinates clicks arrive in.
    private func screenPosition(of point: Vector3, camera: Camera) -> CGPoint {
        let aspect = Float(viewSize.width / viewSize.height)
        let clip = camera.projectionMatrix(aspect: aspect) * camera.viewMatrix() * SIMD4<Float>(point.float3, 1)
        return CGPoint(
            x: (Double(clip.x / clip.w) + 1) * 0.5 * viewSize.width,
            y: (Double(clip.y / clip.w) + 1) * 0.5 * viewSize.height
        )
    }

    /// Clicking a few pixels off the corner of a large model snaps to it.
    func testAimingNearACornerSnapsToIt() {
        let camera = camera(height: 1000)
        let corner = Vector3(0, 0, 0)
        // Five pixels off the corner, into the face - what a steady hand
        // manages, and far more than the 2 mm this used to allow.
        let cursor = screenPosition(of: corner, camera: camera)
            .offset(towards: screenPosition(of: Vector3(50, 50, 0), camera: camera), by: 5)

        let point = MeasurementSystem().findIntersection(
            ray: camera.mouseRay(screenPos: cursor, viewSize: viewSize),
            model: wall,
            snap: ScreenSnap(camera: camera, viewSize: viewSize, cursor: cursor)
        )

        XCTAssertEqual(point?.isAirPoint, false, "should have snapped to the corner")
        XCTAssertEqual(point?.position.distance(to: corner) ?? .infinity, 0, accuracy: 1e-6)
    }

    /// Clicking well clear of any corner does not snap, at any model scale.
    func testAimingAtOpenSurfaceStaysWhereItIsClicked() {
        let camera = camera(height: 1000)
        let middle = Vector3(100, 100, 0)
        let cursor = screenPosition(of: middle, camera: camera)

        let point = MeasurementSystem().findIntersection(
            ray: camera.mouseRay(screenPos: cursor, viewSize: viewSize),
            model: wall,
            snap: ScreenSnap(camera: camera, viewSize: viewSize, cursor: cursor)
        )

        XCTAssertEqual(point?.isAirPoint, true, "should have stayed where it was clicked")
        XCTAssertEqual(point?.position.distance(to: middle) ?? .infinity, 0, accuracy: 0.5)
    }

    /// The same five pixels mean a different distance in model units at each
    /// zoom level, which is the whole point of measuring it on screen.
    func testSearchRadiusFollowsDepth() {
        let snap = ScreenSnap(camera: camera(height: 1000), viewSize: viewSize, cursor: .zero)

        XCTAssertEqual(snap.searchRadius(atDepth: 1000), snap.searchRadius(atDepth: 100) * 10, accuracy: 1e-9)
        XCTAssertGreaterThan(snap.searchRadius(atDepth: 1000), 10)
    }
}

private extension CGPoint {
    /// A point `distance` pixels from here, in the direction of `other`.
    func offset(towards other: CGPoint, by distance: Double) -> CGPoint {
        let dx = other.x - x, dy = other.y - y
        let length = hypot(dx, dy)
        guard length > 0 else { return self }
        return CGPoint(x: x + dx / length * distance, y: y + dy / length * distance)
    }
}
