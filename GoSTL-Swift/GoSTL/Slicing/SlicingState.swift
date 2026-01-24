import Foundation
import Observation

/// State for model slicing (clipping along X, Y, Z axes)
@Observable
final class SlicingState: @unchecked Sendable {
    /// Whether slicing UI is visible
    var isVisible: Bool = false

    /// Whether to show visual slice planes
    var showPlanes: Bool = false

    /// Whether to fill cross-sections
    var fillCrossSections: Bool = false

    /// Currently active plane being dragged (axis, isMin)
    /// nil when no slider is being dragged
    var activePlane: (axis: Int, isMin: Bool)? = nil

    /// Current slice bounds for each axis [min, max]
    /// Index 0 = X axis, 1 = Y axis, 2 = Z axis
    var bounds: [[Double]] = [
        [0.0, 0.0], // X min/max
        [0.0, 0.0], // Y min/max
        [0.0, 0.0]  // Z min/max
    ]

    /// Model bounds (limits for sliders)
    /// Index 0 = X axis, 1 = Y axis, 2 = Z axis
    var modelBounds: [[Double]] = [
        [0.0, 0.0], // X min/max
        [0.0, 0.0], // Y min/max
        [0.0, 0.0]  // Z min/max
    ]

    /// Initialize slicing bounds from model bounding box
    func initializeBounds(from bbox: BoundingBox) {
        let minCorner = bbox.min
        let maxCorner = bbox.max

        // Set model bounds (limits)
        modelBounds = [
            [minCorner.x, maxCorner.x],
            [minCorner.y, maxCorner.y],
            [minCorner.z, maxCorner.z]
        ]

        // Initialize slice bounds to full model (no clipping)
        bounds = modelBounds
    }

    /// Reset slice bounds to full model
    func reset() {
        bounds = modelBounds
    }

    /// Update model bounds while preserving current slice positions (for reload)
    /// Clamps existing slice bounds to fit within new model bounds
    func updateModelBounds(from bbox: BoundingBox) {
        let minCorner = bbox.min
        let maxCorner = bbox.max

        let newModelBounds = [
            [minCorner.x, maxCorner.x],
            [minCorner.y, maxCorner.y],
            [minCorner.z, maxCorner.z]
        ]

        // Clamp existing bounds to new model bounds
        for axis in 0..<3 {
            bounds[axis][0] = max(bounds[axis][0], newModelBounds[axis][0])
            bounds[axis][0] = min(bounds[axis][0], newModelBounds[axis][1])
            bounds[axis][1] = max(bounds[axis][1], newModelBounds[axis][0])
            bounds[axis][1] = min(bounds[axis][1], newModelBounds[axis][1])
        }

        modelBounds = newModelBounds
    }

    /// Full reset for loading a new file
    func fullReset() {
        isVisible = false
        showPlanes = false
        fillCrossSections = false
        activePlane = nil
        bounds = [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
        modelBounds = [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
    }

    /// Toggle slicing UI visibility
    func toggleVisibility() {
        isVisible.toggle()
    }

    /// Check if a point is within slice bounds
    func isPointInBounds(_ point: Vector3) -> Bool {
        guard isVisible else { return true }

        return point.x >= bounds[0][0] && point.x <= bounds[0][1] &&
               point.y >= bounds[1][0] && point.y <= bounds[1][1] &&
               point.z >= bounds[2][0] && point.z <= bounds[2][1]
    }

    /// Check if a triangle is fully within slice bounds
    func isTriangleInBounds(_ triangle: Triangle) -> Bool {
        guard isVisible else { return true }

        return isPointInBounds(triangle.v1) &&
               isPointInBounds(triangle.v2) &&
               isPointInBounds(triangle.v3)
    }
}
