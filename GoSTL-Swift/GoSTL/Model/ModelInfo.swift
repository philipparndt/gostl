import Foundation

/// Information about a loaded 3D model
struct ModelInfo {
    /// Original file name
    let fileName: String

    /// Number of triangles in the model
    let triangleCount: Int

    /// Bounding box of the model
    let boundingBox: BoundingBox

    /// Volume of the model in cubic units
    let volume: Double

    /// Surface area of the model
    let surfaceArea: Double

    /// Selected material for weight calculation
    var material: Material = .pla

    /// Computed properties for display

    var dimensions: Vector3 {
        boundingBox.size
    }

    var width: Double {
        dimensions.x
    }

    var height: Double {
        dimensions.y
    }

    var depth: Double {
        dimensions.z
    }

    var center: Vector3 {
        boundingBox.center
    }

    /// Calculated weight based on volume and material density
    var weight: Double {
        material.weight(volume: volume)
    }

    /// Cycle to the next material type
    mutating func cycleMaterial() {
        let allMaterials = Material.allCases
        let currentIndex = allMaterials.firstIndex(of: material) ?? 0
        let nextIndex = (currentIndex + 1) % allMaterials.count
        material = allMaterials[nextIndex]
    }

    /// Create model info from an STL model
    init(fileName: String, model: STLModel) {
        self.fileName = fileName
        self.triangleCount = model.triangleCount
        self.boundingBox = model.boundingBox()
        self.volume = model.volume()
        self.surfaceArea = model.surfaceArea()
    }

    /// Create model info for an empty file (no geometry)
    init(fileName: String, triangleCount: Int = 0, volume: Double = 0, boundingBox: BoundingBox = BoundingBox()) {
        self.fileName = fileName
        self.triangleCount = triangleCount
        self.boundingBox = boundingBox
        self.volume = volume
        self.surfaceArea = 0
    }

    /// Format a dimension value for display (with appropriate precision)
    static func formatDimension(_ value: Double) -> String {
        if value < 1.0 {
            return String(format: "%.2f mm", value)
        } else if value < 100.0 {
            return String(format: "%.1f mm", value)
        } else {
            return String(format: "%.0f mm", value)
        }
    }

    /// Format volume for display
    static func formatVolume(_ value: Double) -> String {
        if value < 1000.0 {
            return String(format: "%.1f mm³", value)
        } else if value < 1_000_000.0 {
            return String(format: "%.1f cm³", value / 1000.0)
        } else {
            return String(format: "%.2f L", value / 1_000_000.0)
        }
    }

    /// Format area for display
    static func formatArea(_ value: Double) -> String {
        if value < 10000.0 {
            return String(format: "%.1f mm²", value)
        } else {
            return String(format: "%.1f cm²", value / 100.0)
        }
    }

    /// Format count with thousands separator
    static func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
