import Foundation
import simd

/// Build plate orientation options
enum BuildPlateOrientation: String, CaseIterable {
    case bottom = "Bottom"  // XZ plane (Y up) - model standing
    case back = "Back"      // XY plane (Z up) - model lying flat

    var displayName: String { rawValue }

    func next() -> BuildPlateOrientation {
        self == .bottom ? .back : .bottom
    }
}

/// Common 3D printer build plate definitions
enum BuildPlate: String, CaseIterable, Identifiable {
    case off = "Off"
    case bambuLabX1C = "X1C"
    case bambuLabP1S = "P1S"
    case bambuLabA1 = "A1"
    case bambuLabA1Mini = "A1 mini"
    case bambuLabH2D = "H2D"
    case prusa_mk4 = "Prusa MK4"
    case prusa_mini = "Prusa Mini"
    case voron_v0 = "Voron V0"
    case voron_24 = "Voron 2.4"
    case ender3 = "Ender 3"

    var id: String { rawValue }

    /// Build plate dimensions in mm (width x depth x height)
    var dimensions: SIMD3<Float> {
        switch self {
        case .off:
            return SIMD3<Float>(0, 0, 0)
        case .bambuLabX1C:
            return SIMD3<Float>(256, 256, 256)
        case .bambuLabP1S:
            return SIMD3<Float>(256, 256, 256)
        case .bambuLabA1:
            return SIMD3<Float>(256, 256, 256)
        case .bambuLabA1Mini:
            return SIMD3<Float>(180, 180, 180)
        case .bambuLabH2D:
            return SIMD3<Float>(450, 450, 450)
        case .prusa_mk4:
            return SIMD3<Float>(250, 210, 220)
        case .prusa_mini:
            return SIMD3<Float>(180, 180, 180)
        case .voron_v0:
            return SIMD3<Float>(120, 120, 120)
        case .voron_24:
            return SIMD3<Float>(350, 350, 340)
        case .ender3:
            return SIMD3<Float>(220, 220, 250)
        }
    }

    /// Display name for the printer
    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .bambuLabX1C:
            return "Bambu Lab X1C"
        case .bambuLabP1S:
            return "Bambu Lab P1S"
        case .bambuLabA1:
            return "Bambu Lab A1"
        case .bambuLabA1Mini:
            return "Bambu Lab A1 mini"
        case .bambuLabH2D:
            return "Bambu Lab H2D"
        case .prusa_mk4:
            return "Prusa MK4"
        case .prusa_mini:
            return "Prusa Mini"
        case .voron_v0:
            return "Voron V0"
        case .voron_24:
            return "Voron 2.4 (350)"
        case .ender3:
            return "Ender 3"
        }
    }

    /// Manufacturer name for grouping
    var manufacturer: String {
        switch self {
        case .off:
            return ""
        case .bambuLabX1C, .bambuLabP1S, .bambuLabA1, .bambuLabA1Mini, .bambuLabH2D:
            return "Bambu Lab"
        case .prusa_mk4, .prusa_mini:
            return "Prusa"
        case .voron_v0, .voron_24:
            return "Voron"
        case .ender3:
            return "Creality"
        }
    }

    /// Color for the build plate outline
    var color: SIMD4<Float> {
        SIMD4<Float>(0.3, 0.5, 0.8, 0.6) // Blue-ish semi-transparent
    }

    /// Color for the build volume wireframe
    var volumeColor: SIMD4<Float> {
        SIMD4<Float>(0.3, 0.5, 0.8, 0.3) // Lighter blue for volume
    }

    /// Get next build plate in the list (cycles around)
    func next() -> BuildPlate {
        let all = BuildPlate.allCases
        guard let currentIndex = all.firstIndex(of: self) else {
            return .off
        }
        let nextIndex = (currentIndex + 1) % all.count
        return all[nextIndex]
    }

    /// Get previous build plate in the list (cycles around)
    func previous() -> BuildPlate {
        let all = BuildPlate.allCases
        guard let currentIndex = all.firstIndex(of: self) else {
            return .off
        }
        let prevIndex = (currentIndex - 1 + all.count) % all.count
        return all[prevIndex]
    }

    /// Format dimensions for display
    var dimensionsString: String {
        guard self != .off else { return "" }
        return String(format: "%.0f x %.0f x %.0f mm", dimensions.x, dimensions.y, dimensions.z)
    }
}
