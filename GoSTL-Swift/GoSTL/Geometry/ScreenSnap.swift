import Foundation
import simd

/// Decides which vertex a click means, judged the way the user judges it: by
/// how close the vertex looks to the cursor, in pixels.
///
/// Two things went wrong when this was a fixed distance in model units. A 2 mm
/// radius is generous on a 20 mm bracket and hopeless on a 1.5 m dollhouse,
/// where it comes to a couple of pixels and every click lands in mid-air. And
/// ranking candidates by their distance from the point under the cursor
/// misjudges any surface seen at an angle, where a corner that is a few pixels
/// away on screen can be tens of millimetres away in the model.
///
/// So the search collects candidates generously in model space and then picks
/// between them on screen.
struct ScreenSnap {
    /// How close to the cursor a vertex must appear, in drawable pixels.
    ///
    /// `MetalView` works in drawable pixels, so on a Retina display this is
    /// half as many points.
    static let radiusInPixels: Double = 12

    /// How much wider the model-space search is than the on-screen radius.
    ///
    /// Slack for foreshortening: a face seen edge-on packs a lot of model into
    /// very few pixels, so the vertex that looks nearest can sit well outside a
    /// ball the size of the on-screen radius.
    private static let searchReach: Double = 4

    private let cursor: CGPoint
    private let viewSize: CGSize
    private let viewProjection: simd_float4x4
    private let worldUnitsPerPixelAtUnitDepth: Double

    init(camera: Camera, viewSize: CGSize, cursor: CGPoint) {
        self.cursor = cursor
        self.viewSize = viewSize
        let aspect = viewSize.height > 0 ? Float(viewSize.width / viewSize.height) : 1
        self.viewProjection = camera.projectionMatrix(aspect: aspect) * camera.viewMatrix()
        self.worldUnitsPerPixelAtUnitDepth = camera.worldUnitsPerPixel(atDepth: 1, viewSize: viewSize)
    }

    /// How far around a hit `depth` from the camera to collect candidates.
    func searchRadius(atDepth depth: Double) -> Double {
        worldUnitsPerPixelAtUnitDepth * depth * Self.radiusInPixels * Self.searchReach
    }

    /// Distance from the cursor to where `point` lands on screen, in pixels,
    /// or nil if it lands behind the camera.
    func pixelsFromCursor(to point: Vector3) -> Double? {
        let clip = viewProjection * SIMD4<Float>(point.float3, 1)
        guard clip.w > 0 else { return nil }

        let ndc = SIMD2<Double>(Double(clip.x / clip.w), Double(clip.y / clip.w))
        // Click coordinates arrive with Y up, the way `Camera.mouseRay` takes
        // them, so NDC maps straight across without a flip.
        let screen = CGPoint(
            x: (ndc.x + 1) * 0.5 * viewSize.width,
            y: (ndc.y + 1) * 0.5 * viewSize.height
        )

        return hypot(screen.x - cursor.x, screen.y - cursor.y)
    }

    /// Whether `point` is close enough to the cursor on screen to snap to.
    func accepts(_ point: Vector3) -> Bool {
        guard let pixels = pixelsFromCursor(to: point) else { return false }
        return pixels <= Self.radiusInPixels
    }

    /// Picks the candidate that reads as nearest the cursor, or nil if none is
    /// near enough to count as aimed at.
    func nearest<Candidates: Sequence>(of candidates: Candidates) -> Vector3?
    where Candidates.Element == Vector3 {
        var best: Vector3?
        var bestPixels = Self.radiusInPixels

        for candidate in candidates {
            guard let pixels = pixelsFromCursor(to: candidate), pixels <= bestPixels else { continue }
            bestPixels = pixels
            best = candidate
        }

        return best
    }
}
