import Foundation
import simd

/// Common 3D printing materials with their densities
enum Material: String, CaseIterable {
    case pla = "PLA"
    case abs = "ABS"
    case petg = "PETG"
    case tpu = "TPU"
    case nylon = "Nylon"

    /// Density in g/cm³
    var density: Double {
        switch self {
        case .pla:
            return 1.24
        case .abs:
            return 1.04
        case .petg:
            return 1.27
        case .tpu:
            return 1.21
        case .nylon:
            return 1.14
        }
    }

    /// Base color of the material (RGB)
    var baseColor: SIMD3<Float> {
        switch self {
        case .pla:
            return SIMD3<Float>(0.9, 0.9, 0.95)  // Light gray/white
        case .abs:
            return SIMD3<Float>(0.85, 0.85, 0.8) // Slightly warmer gray
        case .petg:
            return SIMD3<Float>(0.88, 0.92, 0.98) // Slightly blue tinted (transparent looking)
        case .tpu:
            return SIMD3<Float>(0.75, 0.75, 0.8) // Darker, more neutral
        case .nylon:
            return SIMD3<Float>(0.95, 0.93, 0.88) // Slightly cream/beige
        }
    }

    /// Glossiness/shininess of the material (0 = matte, 1 = very glossy)
    var glossiness: Float {
        switch self {
        case .pla:
            return 0.2  // Matte finish
        case .abs:
            return 0.3  // Semi-glossy
        case .petg:
            return 0.8  // Very glossy/shiny
        case .tpu:
            return 0.1  // Very matte (flexible)
        case .nylon:
            return 0.4  // Semi-glossy
        }
    }

    /// Metalness of the material (0 = dielectric, 1 = metallic)
    var metalness: Float {
        switch self {
        case .pla, .abs, .petg, .tpu, .nylon:
            return 0.0  // All plastics are non-metallic
        }
    }

    /// Specular intensity multiplier
    var specularIntensity: Float {
        switch self {
        case .pla:
            return 0.3
        case .abs:
            return 0.4
        case .petg:
            return 0.9  // High specular for glossy PETG
        case .tpu:
            return 0.15
        case .nylon:
            return 0.5
        }
    }

    /// Calculate weight in grams for a given volume in mm³
    func weight(volume: Double) -> Double {
        // Convert mm³ to cm³ (divide by 1000)
        let volumeInCm3 = volume / 1000.0
        return volumeInCm3 * density
    }

    /// Format weight for display with appropriate unit
    static func formatWeight(_ grams: Double) -> String {
        if grams < 1.0 {
            return String(format: "%.2f g", grams)
        } else if grams < 1000.0 {
            return String(format: "%.1f g", grams)
        } else {
            return String(format: "%.2f kg", grams / 1000.0)
        }
    }

    /// Get next material in the list (cycles around)
    func next() -> Material {
        let all = Material.allCases
        guard let currentIndex = all.firstIndex(of: self) else {
            return .pla
        }
        let nextIndex = (currentIndex + 1) % all.count
        return all[nextIndex]
    }
}
