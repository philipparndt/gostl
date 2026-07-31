import CoreGraphics
import Foundation

/// Where the orientation cube sits, in drawable pixels.
///
/// One place rather than two: the renderer draws the cube and the input handler
/// hit-tests it, and when those two disagree the cube answers clicks somewhere
/// other than where it appears.
struct OrientationCubeLayout {
	/// Distance from the left edge of the drawable.
	let originX: Double
	/// Distance from the *top* edge, which is what Metal's viewport wants.
	let originY: Double
	/// Width and height; the viewport is square.
	let size: Double

	/// Largest the cube gets, however much room there is.
	static let preferredSize: Double = 300
	/// Gap to the edges when there is room for it.
	static let preferredMargin: Double = 20

	/// `viewSize` is the drawable size in pixels.
	init(
		viewSize: CGSize,
		preferredSize: Double = OrientationCubeLayout.preferredSize,
		preferredMargin: Double = OrientationCubeLayout.preferredMargin
	) {
		let width = max(0, Double(viewSize.width))
		let height = max(0, Double(viewSize.height))
		let room = min(width, height)

		// A fixed size runs off the edge as soon as the pane is narrower than
		// the cube — which a preview split down one side very much can be. Held
		// to a quarter of the shorter side so it stays a corner ornament rather
		// than taking over the view.
		size = min(preferredSize, room * 0.25)
		let margin = min(preferredMargin, room * 0.05)

		// Both are non-negative and inside the drawable: size and margin
		// together are at most 30% of the shorter side.
		originX = max(0, width - size - margin)
		originY = margin
	}

	/// Whether there is enough room to be worth drawing.
	var isVisible: Bool { size > 1 }

	/// The bottom edge in AppKit's coordinates, where Y grows upwards.
	func bottomUpMinY(viewHeight: Double) -> Double { viewHeight - originY - size }

	/// Whether a point in AppKit's coordinates falls on the cube.
	func contains(_ point: CGPoint, viewHeight: Double) -> Bool {
		guard isVisible else { return false }
		let minY = bottomUpMinY(viewHeight: viewHeight)
		return Double(point.x) >= originX && Double(point.x) <= originX + size
			&& Double(point.y) >= minY && Double(point.y) <= minY + size
	}
}
