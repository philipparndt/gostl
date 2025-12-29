import Foundation

/// Types of measurements that can be performed
enum MeasurementType {
    case distance  // Distance between two points
    case angle     // Angle between three points
    case radius    // Radius of a circle fitted to three points
    case triangleSelect  // Select triangles for OpenSCAD export
}

/// A point in 3D space used for measurements
struct MeasurementPoint {
    let position: Vector3
    let normal: Vector3
    let isAirPoint: Bool  // true if created via constraint or didn't snap to vertex

    init(position: Vector3, normal: Vector3, isAirPoint: Bool = false) {
        self.position = position
        self.normal = normal
        self.isAirPoint = isAirPoint
    }
}

/// A completed measurement
struct Measurement {
    let type: MeasurementType
    let points: [MeasurementPoint]
    let value: Double
    let circle: Circle? // For radius measurements, stores the fitted circle
    var stalePointIndices: Set<Int> = []  // Indices of points that no longer align with model vertices

    /// Whether any points in this measurement are stale (no longer on vertices)
    var hasStalePoints: Bool {
        !stalePointIndices.isEmpty
    }

    init(type: MeasurementType, points: [MeasurementPoint], value: Double, circle: Circle? = nil) {
        self.type = type
        self.points = points
        self.value = value
        self.circle = circle
    }

    /// Format the measurement value for display
    var formattedValue: String {
        switch type {
        case .distance:
            return formatDistance(value)
        case .angle:
            return String(format: "%.1f°", value)
        case .radius:
            return formatDistance(value)
        case .triangleSelect:
            return ""  // Not used for triangle selection
        }
    }

    /// Label for the measurement type
    var label: String {
        switch type {
        case .distance:
            return "Distance"
        case .angle:
            return "Angle"
        case .radius:
            return "Radius"
        case .triangleSelect:
            return "Triangle"  // Not used for triangle selection
        }
    }

    /// Position where the label should be displayed (in 3D world space)
    var labelPosition: Vector3 {
        guard points.count >= 2 else {
            return points.first?.position ?? Vector3(0, 0, 0)
        }

        switch type {
        case .distance:
            // Midpoint between the two points
            let p1 = points[0].position
            let p2 = points[1].position
            return (p1 + p2) / 2.0

        case .angle:
            // Position near the middle point (vertex of the angle)
            if points.count >= 3 {
                let vertex = points[1].position
                let p1 = points[0].position
                let p2 = points[2].position
                // Offset from vertex towards the bisector
                let dir1 = (p1 - vertex).normalized()
                let dir2 = (p2 - vertex).normalized()
                let bisector = (dir1 + dir2).normalized()
                return vertex + bisector * 2.0 // Offset by 2 units
            }
            return points[1].position

        case .radius:
            // Center of the three points
            if points.count >= 3 {
                let sum = points[0].position + points[1].position + points[2].position
                return sum / 3.0
            }
            return points[0].position

        case .triangleSelect:
            return Vector3(0, 0, 0)  // Not used for triangle selection
        }
    }

    private func formatDistance(_ value: Double) -> String {
        if value < 1.0 {
            return String(format: "%.2f", value)
        } else if value < 100.0 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.0f", value)
        }
    }
}
