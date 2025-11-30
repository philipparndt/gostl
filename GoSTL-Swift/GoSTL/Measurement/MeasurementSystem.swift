import Foundation
import Observation
import simd

/// Constraint type for axis-constrained measurements
enum ConstraintType {
    case axis(Int)  // 0=X, 1=Y, 2=Z
}

/// Manages measurement state and calculations
@Observable
final class MeasurementSystem: @unchecked Sendable {
    /// Current measurement mode (nil = not measuring)
    var mode: MeasurementType?

    /// Points collected for current measurement
    var currentPoints: [MeasurementPoint] = []

    /// Completed measurements
    var measurements: [Measurement] = []

    /// Hover point (preview of where next point would be picked)
    var hoverPoint: MeasurementPoint?

    /// Active constraint for measurement (nil = no constraint)
    var constraint: ConstraintType?

    /// The constrained endpoint position (where the measurement line will actually end)
    /// This is calculated based on the constraint axis
    var constrainedEndpoint: Vector3?

    /// Currently hovered axis label on orientation cube (-1 = none, 0=X, 1=Y, 2=Z)
    var hoveredAxisLabel: Int = -1

    /// Number of points required for current mode
    var pointsNeeded: Int {
        guard let mode else { return 0 }
        switch mode {
        case .distance:
            return 0 // Continuous mode - no fixed limit
        case .angle:
            return 3
        case .radius:
            return 3
        }
    }

    /// Descriptive text for points needed
    var pointsNeededText: String {
        guard let mode else { return "" }
        switch mode {
        case .distance:
            return "\(currentPoints.count)" // Just show count
        case .angle:
            return "\(currentPoints.count) / 3"
        case .radius:
            return "\(currentPoints.count) / 3"
        }
    }

    /// Whether we're currently collecting points
    var isCollecting: Bool {
        mode != nil
    }

    /// Start a new measurement
    func startMeasurement(type: MeasurementType) {
        mode = type
        currentPoints = []
    }

    /// Cancel current measurement
    func cancelMeasurement() {
        mode = nil
        currentPoints = []
        hoverPoint = nil
        constraint = nil
        constrainedEndpoint = nil
    }

    /// Update hover point based on mouse position
    func updateHover(ray: Ray, model: STLModel?) {
        guard isCollecting, let model else {
            hoverPoint = nil
            constrainedEndpoint = nil
            return
        }
        hoverPoint = findIntersection(ray: ray, model: model)

        // Update constrained endpoint if constraint is active
        updateConstrainedMeasurement()
    }

    /// Add a point to the current measurement
    /// - Returns: true if measurement is complete
    func addPoint(_ point: MeasurementPoint) -> Bool {
        // For distance mode, check if clicking on an already selected point (to end measurement)
        if mode == .distance && !currentPoints.isEmpty {
            // Check if the new point matches any existing point
            let epsilon = 0.001 // Small tolerance for floating point comparison
            for existingPoint in currentPoints {
                let distance = point.position.distance(to: existingPoint.position)
                if distance < epsilon {
                    // Clicked on existing point - create final segment first, then end measurement
                    if let lastPoint = currentPoints.last {
                        let segmentPoints = [lastPoint, existingPoint]
                        let result = calculateValue(type: .distance, points: segmentPoints)
                        let measurement = Measurement(type: .distance, points: segmentPoints, value: result.value, circle: result.circle)
                        measurements.append(measurement)
                    }
                    endMeasurement()
                    print("Distance measurement ended (clicked on existing point)")
                    return true
                }
            }
        }

        currentPoints.append(point)

        // For distance mode, keep going (create segment measurements)
        if mode == .distance {
            if currentPoints.count >= 2 {
                // Create a measurement for the last segment
                let segmentPoints = Array(currentPoints.suffix(2))
                let result = calculateValue(type: .distance, points: segmentPoints)
                let measurement = Measurement(type: .distance, points: segmentPoints, value: result.value, circle: result.circle)
                measurements.append(measurement)
            }
            // Continue measuring - don't reset
            return false
        }

        // For angle and radius, complete after enough points
        if pointsNeeded > 0 && currentPoints.count >= pointsNeeded {
            completeMeasurement()
            return true
        }
        return false
    }

    /// Manually end the current measurement session
    func endMeasurement() {
        mode = nil
        currentPoints = []
        hoverPoint = nil
        constraint = nil
        constrainedEndpoint = nil
    }

    /// Complete the current measurement
    private func completeMeasurement() {
        guard let mode, currentPoints.count >= pointsNeeded else { return }

        let result = calculateValue(type: mode, points: currentPoints)
        let measurement = Measurement(type: mode, points: currentPoints, value: result.value, circle: result.circle)
        measurements.append(measurement)

        // Reset for next measurement
        self.mode = nil
        self.currentPoints = []
    }

    /// Calculate measurement value based on type
    private func calculateValue(type: MeasurementType, points: [MeasurementPoint]) -> (value: Double, circle: Circle?) {
        switch type {
        case .distance:
            guard points.count >= 2 else { return (0, nil) }
            return (points[0].position.distance(to: points[1].position), nil)

        case .angle:
            guard points.count >= 3 else { return (0, nil) }
            // Calculate angle at middle point (points[1])
            let v1 = (points[0].position - points[1].position).normalized()
            let v2 = (points[2].position - points[1].position).normalized()
            let cosAngle = v1.dot(v2)
            let angleRadians = acos(max(-1.0, min(1.0, cosAngle)))
            let degrees = angleRadians * 180.0 / .pi // Convert to degrees
            return (degrees, nil)

        case .radius:
            guard points.count >= 3 else { return (0, nil) }
            // Fit a circle to the three points
            let positions = points.map { $0.position }
            if let circle = Circle.fit(points: positions) {
                return (circle.radius, circle)
            }
            return (0, nil)
        }
    }

    /// Find intersection point on model for a ray
    func findIntersection(ray: Ray, model: STLModel) -> MeasurementPoint? {
        var closestDistance: Float = .infinity
        var closestIntersection: (position: Vector3, normal: Vector3)?

        // Test all triangles
        for triangle in model.triangles {
            if let (position, normal) = triangle.intersectionPoint(ray: ray) {
                let distance = ray.origin.distance(to: position.float3)
                if distance < closestDistance {
                    closestDistance = distance
                    closestIntersection = (position, normal)
                }
            }
        }

        if let intersection = closestIntersection {
            return MeasurementPoint(position: intersection.position, normal: intersection.normal)
        }
        return nil
    }

    /// Clear all measurements
    func clearAll() {
        mode = nil
        currentPoints = []
        measurements = []
        constraint = nil
        constrainedEndpoint = nil
    }

    // MARK: - Axis Constraint Methods

    /// Toggle axis constraint (set or clear constraint on specified axis)
    func toggleAxisConstraint(_ axis: Int) {
        // Only valid when measuring distance with at least one point selected
        guard mode == .distance && !currentPoints.isEmpty else { return }

        if case .axis(let currentAxis) = constraint, currentAxis == axis {
            // Same axis - toggle off
            constraint = nil
            constrainedEndpoint = nil
            print("Constraint disabled")
        } else {
            // Set new axis constraint
            constraint = .axis(axis)
            print("Constraint: \(["X", "Y", "Z"][axis]) axis")
        }
    }

    /// Check if constraint is active on a specific axis
    func isConstraintActive(on axis: Int) -> Bool {
        if case .axis(let constraintAxis) = constraint {
            return constraintAxis == axis
        }
        return false
    }

    /// Get currently constrained axis (-1 if no constraint)
    var constrainedAxis: Int {
        if case .axis(let axis) = constraint {
            return axis
        }
        return -1
    }

    /// Calculate the constrained endpoint based on current constraint
    /// - Parameter snapPoint: The point under the cursor (where user would normally click)
    /// - Returns: The constrained endpoint position (along the constraint axis only)
    func calculateConstrainedEndpoint(snapPoint: Vector3) -> Vector3? {
        guard !currentPoints.isEmpty,
              case .axis(let axis) = constraint,
              let lastPoint = currentPoints.last else {
            return nil
        }

        let referencePoint = lastPoint.position

        // Calculate endpoint that only changes along the constrained axis
        switch axis {
        case 0: // X axis
            return Vector3(snapPoint.x, referencePoint.y, referencePoint.z)
        case 1: // Y axis
            return Vector3(referencePoint.x, snapPoint.y, referencePoint.z)
        case 2: // Z axis
            return Vector3(referencePoint.x, referencePoint.y, snapPoint.z)
        default:
            return nil
        }
    }

    /// Update constraint state when hover point changes
    func updateConstrainedMeasurement() {
        guard let hoverPoint = hoverPoint,
              !currentPoints.isEmpty,
              constraint != nil else {
            constrainedEndpoint = nil
            return
        }

        constrainedEndpoint = calculateConstrainedEndpoint(snapPoint: hoverPoint.position)
    }

    /// Remove most recent measurement
    func removeLastMeasurement() {
        if !measurements.isEmpty {
            measurements.removeLast()
        }
    }

    /// Remove the last picked point (undo last click)
    func removeLastPoint() {
        if !currentPoints.isEmpty {
            currentPoints.removeLast()

            // For distance mode, also remove the last segment measurement
            if mode == .distance && !measurements.isEmpty {
                measurements.removeLast()
                print("Removed last segment, \(currentPoints.count) points remaining")
            } else {
                print("Removed last point, \(currentPoints.count) points remaining")
            }
        }
    }

    /// Get preview distance (distance from last point to hover point)
    var previewDistance: Double? {
        guard let hoverPoint = hoverPoint,
              !currentPoints.isEmpty else {
            return nil
        }
        let lastPoint = currentPoints.last!.position
        return hoverPoint.position.distance(to: lastPoint)
    }
}

// Extension to add distance method to SIMD3<Float>
extension SIMD3<Float> {
    func distance(to other: SIMD3<Float>) -> Float {
        let diff = self - other
        return sqrt(simd_dot(diff, diff))
    }
}
