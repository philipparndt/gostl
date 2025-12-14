import Foundation

/// Manages the state for leveling mode, which allows users to rotate a model
/// so that two selected points become aligned along a chosen axis.
@Observable
final class LevelingState: @unchecked Sendable {
    /// Whether leveling mode is currently active
    var isActive: Bool = false

    /// First point selected for leveling
    var point1: Vector3?

    /// Second point selected for leveling
    var point2: Vector3?

    /// Current hover point (for preview visualization)
    var hoverPoint: Vector3?

    /// Selected axis to level to (0=X, 1=Y, 2=Z), nil if not yet selected
    var selectedAxis: Int?

    /// Previous model triangles for undo support
    var previousModelTriangles: [Triangle]?

    /// Whether an undo operation is available
    var canUndo: Bool {
        previousModelTriangles != nil
    }

    /// Number of points currently selected (0, 1, or 2)
    var pointCount: Int {
        (point1 != nil ? 1 : 0) + (point2 != nil ? 1 : 0)
    }

    /// Whether we're ready to show axis selection UI
    var isReadyForAxisSelection: Bool {
        point1 != nil && point2 != nil && selectedAxis == nil
    }

    /// Status text describing current state
    var statusText: String {
        if !isActive {
            return ""
        }
        if point1 == nil {
            return "Click to pick first point"
        }
        if point2 == nil {
            return "Click to pick second point"
        }
        if selectedAxis == nil {
            return "Select axis to level"
        }
        return "Applying..."
    }

    /// Start leveling mode
    func startLeveling() {
        isActive = true
        point1 = nil
        point2 = nil
        hoverPoint = nil
        selectedAxis = nil
    }

    /// Add a point to the leveling selection
    /// - Parameter position: The 3D position of the selected point
    /// - Returns: true if both points are now selected
    func addPoint(_ position: Vector3) -> Bool {
        if point1 == nil {
            point1 = position
            return false
        } else if point2 == nil {
            point2 = position
            return true
        }
        return true
    }

    /// Select the axis to level to
    /// - Parameter axis: 0 for X, 1 for Y, 2 for Z
    func selectAxis(_ axis: Int) {
        guard axis >= 0 && axis <= 2 else { return }
        selectedAxis = axis
    }

    /// Reset leveling state (cancel or complete)
    func reset() {
        isActive = false
        point1 = nil
        point2 = nil
        hoverPoint = nil
        selectedAxis = nil
    }

    /// Store triangles for undo functionality
    /// - Parameter triangles: The current triangles before transformation
    func storeForUndo(_ triangles: [Triangle]) {
        previousModelTriangles = triangles
    }

    /// Clear undo state
    func clearUndo() {
        previousModelTriangles = nil
    }

    /// Get the axis name for display
    static func axisName(for axis: Int) -> String {
        switch axis {
        case 0: return "X"
        case 1: return "Y"
        case 2: return "Z"
        default: return "?"
        }
    }
}
