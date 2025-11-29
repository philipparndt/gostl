import Foundation

/// Types of measurements that can be performed
enum MeasurementType {
    case distance  // Distance between two points
    case angle     // Angle between three points
    case radius    // Radius of a circle fitted to three points
}

/// A point in 3D space used for measurements
struct MeasurementPoint {
    let position: Vector3
    let normal: Vector3

    init(position: Vector3, normal: Vector3) {
        self.position = position
        self.normal = normal
    }
}

/// A completed measurement
struct Measurement {
    let type: MeasurementType
    let points: [MeasurementPoint]
    let value: Double

    init(type: MeasurementType, points: [MeasurementPoint], value: Double) {
        self.type = type
        self.points = points
        self.value = value
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
        }
    }

    private func formatDistance(_ value: Double) -> String {
        if value < 1.0 {
            return String(format: "%.2f mm", value)
        } else if value < 100.0 {
            return String(format: "%.1f mm", value)
        } else {
            return String(format: "%.0f mm", value)
        }
    }
}
