import simd
import SwiftUI

/// Centralized axis color constants
/// Modern, pleasant colors for X, Y, Z axes used throughout the application
enum AxisColors {
    /// X axis - Modern warm red (#E74C3C)
    static let x = SIMD4<Float>(0.906, 0.298, 0.235, 1.0)

    /// Y axis - Modern vibrant green (#2ECC71)
    static let y = SIMD4<Float>(0.180, 0.800, 0.443, 1.0)

    /// Z axis - Modern clear blue (#3498DB)
    static let z = SIMD4<Float>(0.204, 0.596, 0.859, 1.0)

    /// Get axis color by index (0=X, 1=Y, 2=Z)
    static func color(for axis: Int) -> SIMD4<Float> {
        switch axis {
        case 0: return x
        case 1: return y
        case 2: return z
        default: return SIMD4(0.5, 0.5, 0.5, 1.0) // Gray fallback
        }
    }

    /// Array of all axis colors [X, Y, Z]
    static let all: [SIMD4<Float>] = [x, y, z]

    // MARK: - SwiftUI Color versions

    /// X axis color for SwiftUI
    static let xUI = Color(red: 0.906, green: 0.298, blue: 0.235)

    /// Y axis color for SwiftUI
    static let yUI = Color(red: 0.180, green: 0.800, blue: 0.443)

    /// Z axis color for SwiftUI
    static let zUI = Color(red: 0.204, green: 0.596, blue: 0.859)

    /// Get SwiftUI Color by index (0=X, 1=Y, 2=Z)
    static func uiColor(for axis: Int) -> Color {
        switch axis {
        case 0: return xUI
        case 1: return yUI
        case 2: return zUI
        default: return Color.gray
        }
    }

    /// Array of all axis colors for SwiftUI [X, Y, Z]
    static let allUI: [Color] = [xUI, yUI, zUI]
}
