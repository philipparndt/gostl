import Foundation
import Observation
import simd

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
    }

    /// Update hover point based on mouse position
    func updateHover(ray: Ray, model: STLModel?) {
        guard isCollecting, let model else {
            hoverPoint = nil
            return
        }
        hoverPoint = findIntersection(ray: ray, model: model)
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
                        let value = calculateValue(type: .distance, points: segmentPoints)
                        let measurement = Measurement(type: .distance, points: segmentPoints, value: value)
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
                let value = calculateValue(type: .distance, points: segmentPoints)
                let measurement = Measurement(type: .distance, points: segmentPoints, value: value)
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
    }

    /// Complete the current measurement
    private func completeMeasurement() {
        guard let mode, currentPoints.count >= pointsNeeded else { return }

        let value = calculateValue(type: mode, points: currentPoints)
        let measurement = Measurement(type: mode, points: currentPoints, value: value)
        measurements.append(measurement)

        // Reset for next measurement
        self.mode = nil
        self.currentPoints = []
    }

    /// Calculate measurement value based on type
    private func calculateValue(type: MeasurementType, points: [MeasurementPoint]) -> Double {
        switch type {
        case .distance:
            guard points.count >= 2 else { return 0 }
            return points[0].position.distance(to: points[1].position)

        case .angle:
            guard points.count >= 3 else { return 0 }
            // Calculate angle at middle point (points[1])
            let v1 = (points[0].position - points[1].position).normalized()
            let v2 = (points[2].position - points[1].position).normalized()
            let cosAngle = v1.dot(v2)
            let angleRadians = acos(max(-1.0, min(1.0, cosAngle)))
            return angleRadians * 180.0 / .pi // Convert to degrees

        case .radius:
            guard points.count >= 3 else { return 0 }
            // Fit a circle to the three points
            let positions = points.map { $0.position }
            if let circle = Circle.fit(points: positions) {
                return circle.radius
            }
            return 0
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
