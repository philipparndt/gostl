import Foundation

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
