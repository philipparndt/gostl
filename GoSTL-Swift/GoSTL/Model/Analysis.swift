import Foundation

/// Comprehensive analysis results for a 3D model
struct ModelAnalysis {
    var boundingBox: BoundingBox
    var dimensions: Vector3
    var volume: Double
    var surfaceArea: Double
    var triangleCount: Int
    var edgeCount: Int
    var minEdgeLength: Double
    var maxEdgeLength: Double
    var avgEdgeLength: Double
    var weightPLA100: Double  // 100% infill
    var weightPLA15: Double   // 15% infill

    // MARK: - Computed Properties

    var volumeCM3: Double {
        volume / 1000.0
    }

    var surfaceAreaCM2: Double {
        surfaceArea / 100.0
    }

    /// Format dimensions as string
    var dimensionsString: String {
        String(format: "%.2f × %.2f × %.2f mm", dimensions.x, dimensions.y, dimensions.z)
    }

    /// Format volume as string
    var volumeString: String {
        if volume > 1000 {
            String(format: "%.2f cm³", volumeCM3)
        } else {
            String(format: "%.2f mm³", volume)
        }
    }

    /// Format surface area as string
    var surfaceAreaString: String {
        if surfaceArea > 100 {
            String(format: "%.2f cm²", surfaceAreaCM2)
        } else {
            String(format: "%.2f mm²", surfaceArea)
        }
    }
}

// MARK: - STLModel Analysis Extension

extension STLModel {
    /// Perform comprehensive analysis of the model
    func analyze() -> ModelAnalysis {
        let bbox = boundingBox()
        let edges = edgeStatistics()

        return ModelAnalysis(
            boundingBox: bbox,
            dimensions: bbox.size,
            volume: volume(),
            surfaceArea: surfaceArea(),
            triangleCount: triangleCount,
            edgeCount: edges.count,
            minEdgeLength: edges.min,
            maxEdgeLength: edges.max,
            avgEdgeLength: edges.average,
            weightPLA100: calculatePLAWeight(infill: 1.0),
            weightPLA15: calculatePLAWeight(infill: 0.15)
        )
    }
}

// MARK: - Codable

extension ModelAnalysis: Codable {}

// MARK: - CustomStringConvertible

extension ModelAnalysis: CustomStringConvertible {
    var description: String {
        """
        Model Analysis:
          Triangles: \(triangleCount)
          Dimensions: \(dimensionsString)
          Volume: \(volumeString)
          Surface Area: \(surfaceAreaString)
          PLA Weight (100%): \(String(format: "%.2f g", weightPLA100))
          PLA Weight (15%): \(String(format: "%.2f g", weightPLA15))
        """
    }
}
