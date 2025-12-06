import Foundation
import Observation
import simd

/// Constraint type for axis-constrained measurements
enum ConstraintType {
    case axis(Int)  // 0=X, 1=Y, 2=Z
    case point(Vector3)  // Constrains to direction towards this point
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

    /// Set of selected measurement indices
    var selectedMeasurements: Set<Int> = []

    /// Selection rectangle (in screen coordinates) - nil when not selecting
    var selectionRect: (start: CGPoint, end: CGPoint)?

    /// Set of selected triangle indices (for OpenSCAD export)
    var selectedTriangles: Set<Int> = []

    /// Hovered triangle index (for visual feedback during triangle selection)
    var hoveredTriangle: Int?

    /// Paint mode - when enabled, drag to continuously select triangles without rotating
    var paintMode: Bool = false

    /// Whether currently painting (mouse is down in paint mode)
    var isPainting: Bool = false

    /// Whether painting to unselect (Cmd+Shift) instead of select (Cmd)
    var isPaintingToUnselect: Bool = false

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
        case .triangleSelect:
            return 0 // Continuous mode - click to select/deselect triangles
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
        case .triangleSelect:
            return "\(selectedTriangles.count) triangles"
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

        case .triangleSelect:
            // Triangle selection doesn't create measurements
            return (0, nil)
        }
    }

    /// Find intersection point on model for a ray
    /// Snaps to nearby vertices if within threshold
    func findIntersection(ray: Ray, model: STLModel) -> MeasurementPoint? {
        var closestDistance: Float = .infinity
        var closestIntersection: (position: Vector3, normal: Vector3)?

        // Test all triangles to find the closest hit point
        for triangle in model.triangles {
            if let (position, normal) = triangle.intersectionPoint(ray: ray) {
                let distance = ray.origin.distance(to: position.float3)
                if distance < closestDistance {
                    closestDistance = distance
                    closestIntersection = (position, normal)
                }
            }
        }

        guard let intersection = closestIntersection else {
            return nil
        }

        // Snap to nearest vertex in the model if within threshold
        let snapThreshold: Double = 2.0
        var snappedPosition = intersection.position

        var closestVertexDistance: Double = .infinity
        for triangle in model.triangles {
            for vertex in [triangle.v1, triangle.v2, triangle.v3] {
                let distance = vertex.distance(to: intersection.position)
                if distance < closestVertexDistance && distance <= snapThreshold {
                    closestVertexDistance = distance
                    snappedPosition = vertex
                }
            }
        }

        return MeasurementPoint(position: snappedPosition, normal: intersection.normal)
    }

    /// Clear all measurements
    func clearAll() {
        mode = nil
        currentPoints = []
        measurements = []
        constraint = nil
        constrainedEndpoint = nil
        selectedTriangles.removeAll()
        hoveredTriangle = nil
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

    /// Get currently constrained axis (-1 if no constraint or point constraint)
    var constrainedAxis: Int {
        if case .axis(let axis) = constraint {
            return axis
        }
        return -1
    }

    /// Check if point constraint is active
    var hasPointConstraint: Bool {
        if case .point = constraint {
            return true
        }
        return false
    }

    /// Get the constraining point (if point constraint is active)
    var constrainingPoint: Vector3? {
        if case .point(let point) = constraint {
            return point
        }
        return nil
    }

    /// Toggle point constraint using the current hover point
    func togglePointConstraint() {
        guard mode == .distance && !currentPoints.isEmpty else { return }

        // If already have a point constraint, clear it
        if case .point = constraint {
            constraint = nil
            constrainedEndpoint = nil
            print("Point constraint disabled")
            return
        }

        // Set point constraint using current hover point
        guard let hoverPoint = hoverPoint else {
            print("No hover point for constraint")
            return
        }

        constraint = .point(hoverPoint.position)
        print("Point constraint: \(hoverPoint.position)")
    }

    /// Calculate the constrained endpoint based on current constraint
    /// - Parameter snapPoint: The point under the cursor (where user would normally click)
    /// - Returns: The constrained endpoint position (along the constraint axis or direction)
    func calculateConstrainedEndpoint(snapPoint: Vector3) -> Vector3? {
        guard !currentPoints.isEmpty,
              let lastPoint = currentPoints.last,
              let constraint = constraint else {
            return nil
        }

        let referencePoint = lastPoint.position

        switch constraint {
        case .axis(let axis):
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

        case .point(let constrainingPoint):
            // Calculate direction from reference point to constraining point
            let direction = constrainingPoint - referencePoint
            let dirLength = direction.length

            if dirLength < 0.0001 {
                // Constraining point is same as reference point
                return nil
            }

            // Normalize direction
            let normDir = direction / dirLength

            // Project the snap point onto the constraint line
            let toSnapPoint = snapPoint - referencePoint
            let t = toSnapPoint.dot(normDir)

            // Calculate the projected point on the constraint line
            return referencePoint + normDir * t
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

    // MARK: - Selection Methods

    /// Start selection rectangle
    func startSelection(at point: CGPoint) {
        selectionRect = (start: point, end: point)
        selectedMeasurements.removeAll()
    }

    /// Update selection rectangle end point
    func updateSelection(to point: CGPoint) {
        guard selectionRect != nil else { return }
        selectionRect?.end = point
    }

    /// End selection and keep selected measurements
    func endSelection() {
        selectionRect = nil
    }

    /// Cancel selection
    func cancelSelection() {
        selectionRect = nil
        selectedMeasurements.removeAll()
    }

    /// Check if a measurement line intersects with the selection rectangle
    /// Uses screen-space coordinates
    func updateSelectedMeasurements(camera: Camera, viewSize: CGSize) {
        guard let rect = selectionRect else { return }

        selectedMeasurements.removeAll()

        // Normalize rectangle (handle drag in any direction)
        let minX = min(rect.start.x, rect.end.x)
        let maxX = max(rect.start.x, rect.end.x)
        let minY = min(rect.start.y, rect.end.y)
        let maxY = max(rect.start.y, rect.end.y)

        let selectionBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        // Check each measurement
        for (index, measurement) in measurements.enumerated() {
            if measurement.type == .distance && measurement.points.count >= 2 {
                // Project both endpoints to screen space
                let p1 = measurement.points[0].position
                let p2 = measurement.points[1].position

                if let screen1 = camera.worldToScreen(point: p1, viewSize: viewSize),
                   let screen2 = camera.worldToScreen(point: p2, viewSize: viewSize) {
                    // Check if the line segment intersects the selection rectangle
                    if lineIntersectsRect(
                        lineStart: screen1,
                        lineEnd: screen2,
                        rect: selectionBounds
                    ) {
                        selectedMeasurements.insert(index)
                    }
                }
            } else if measurement.type == .radius {
                // For radius measurements, check if center point is in selection
                if let circle = measurement.circle {
                    if let screenCenter = camera.worldToScreen(point: circle.center, viewSize: viewSize) {
                        if selectionBounds.contains(screenCenter) {
                            selectedMeasurements.insert(index)
                        }
                    }
                }
            } else if measurement.type == .angle && measurement.points.count >= 3 {
                // For angle measurements, check if middle point is in selection
                let middlePoint = measurement.points[1].position
                if let screenMiddle = camera.worldToScreen(point: middlePoint, viewSize: viewSize) {
                    if selectionBounds.contains(screenMiddle) {
                        selectedMeasurements.insert(index)
                    }
                }
            }
        }
    }

    /// Check if a line segment intersects a rectangle
    private func lineIntersectsRect(lineStart: CGPoint, lineEnd: CGPoint, rect: CGRect) -> Bool {
        // Check if either endpoint is inside the rectangle
        if rect.contains(lineStart) || rect.contains(lineEnd) {
            return true
        }

        // Check if line intersects any edge of the rectangle
        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)

        // Check intersection with each edge
        if lineSegmentsIntersect(lineStart, lineEnd, topLeft, topRight) { return true }
        if lineSegmentsIntersect(lineStart, lineEnd, topRight, bottomRight) { return true }
        if lineSegmentsIntersect(lineStart, lineEnd, bottomRight, bottomLeft) { return true }
        if lineSegmentsIntersect(lineStart, lineEnd, bottomLeft, topLeft) { return true }

        return false
    }

    /// Check if two line segments intersect
    private func lineSegmentsIntersect(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> Bool {
        let d1 = direction(p3, p4, p1)
        let d2 = direction(p3, p4, p2)
        let d3 = direction(p1, p2, p3)
        let d4 = direction(p1, p2, p4)

        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
           ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }

        if d1 == 0 && onSegment(p3, p4, p1) { return true }
        if d2 == 0 && onSegment(p3, p4, p2) { return true }
        if d3 == 0 && onSegment(p1, p2, p3) { return true }
        if d4 == 0 && onSegment(p1, p2, p4) { return true }

        return false
    }

    private func direction(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGFloat {
        return (p3.x - p1.x) * (p2.y - p1.y) - (p2.x - p1.x) * (p3.y - p1.y)
    }

    private func onSegment(_ p1: CGPoint, _ p2: CGPoint, _ p: CGPoint) -> Bool {
        return min(p1.x, p2.x) <= p.x && p.x <= max(p1.x, p2.x) &&
               min(p1.y, p2.y) <= p.y && p.y <= max(p1.y, p2.y)
    }

    /// Remove selected measurements
    func removeSelectedMeasurements() {
        guard !selectedMeasurements.isEmpty else { return }

        // Remove in reverse order to preserve indices
        let sortedIndices = selectedMeasurements.sorted(by: >)
        for index in sortedIndices {
            if index < measurements.count {
                measurements.remove(at: index)
            }
        }
        selectedMeasurements.removeAll()
        print("Removed \(sortedIndices.count) measurement(s)")
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

    // MARK: - Triangle Selection Methods

    /// Toggle selection of a triangle by index
    func toggleTriangleSelection(_ index: Int) {
        if selectedTriangles.contains(index) {
            selectedTriangles.remove(index)
            print("Deselected triangle \(index), \(selectedTriangles.count) selected")
        } else {
            selectedTriangles.insert(index)
            print("Selected triangle \(index), \(selectedTriangles.count) selected")
        }
    }

    /// Add triangle to selection (without deselecting)
    func selectTriangle(_ index: Int) {
        selectedTriangles.insert(index)
    }

    /// Clear all selected triangles
    func clearTriangleSelection() {
        selectedTriangles.removeAll()
        hoveredTriangle = nil
        print("Triangle selection cleared")
    }

    /// Find which triangle the ray intersects (returns index)
    func findTriangleAtRay(ray: Ray, model: STLModel) -> Int? {
        var closestDistance: Float = .infinity
        var closestIndex: Int?

        for (index, triangle) in model.triangles.enumerated() {
            if let distance = triangle.intersect(ray: ray) {
                if distance < closestDistance {
                    closestDistance = distance
                    closestIndex = index
                }
            }
        }

        return closestIndex
    }

    /// Update hovered triangle based on mouse position
    func updateTriangleHover(ray: Ray, model: STLModel?) {
        guard mode == .triangleSelect, let model else {
            hoveredTriangle = nil
            return
        }
        hoveredTriangle = findTriangleAtRay(ray: ray, model: model)
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
