import Foundation

/// A 3D model loaded from an STL file
struct STLModel {
    var triangles: [Triangle]
    var name: String?

    // MARK: - Initializers

    init(triangles: [Triangle] = [], name: String? = nil) {
        self.triangles = triangles
        self.name = name
    }

    // MARK: - Computed Properties

    /// Total number of triangles in the model
    var triangleCount: Int {
        triangles.count
    }

    /// Calculate the bounding box of the entire model
    func boundingBox() -> BoundingBox {
        guard !triangles.isEmpty else {
            return BoundingBox()
        }

        var box = BoundingBox(point: triangles[0].v1)
        for triangle in triangles {
            box.extend(triangle.v1)
            box.extend(triangle.v2)
            box.extend(triangle.v3)
        }
        return box
    }

    /// Calculate total surface area
    func surfaceArea() -> Double {
        triangles.reduce(0) { $0 + $1.area() }
    }

    /// Calculate volume using signed volume method (assumes closed mesh)
    func volume() -> Double {
        var volume: Double = 0

        for triangle in triangles {
            // Signed volume of tetrahedron formed by triangle and origin
            let v1 = triangle.v1
            let v2 = triangle.v2
            let v3 = triangle.v3

            let cross = v2.cross(v3)
            let signedVolume = v1.dot(cross) / 6.0

            volume += signedVolume
        }

        return abs(volume)
    }

    /// Calculate edge statistics
    func edgeStatistics() -> (min: Double, max: Double, average: Double, count: Int) {
        guard !triangles.isEmpty else {
            return (0, 0, 0, 0)
        }

        var allEdgeLengths: [Double] = []
        allEdgeLengths.reserveCapacity(triangles.count * 3)

        for triangle in triangles {
            let edges = triangle.edgeLengths()
            allEdgeLengths.append(edges.0)
            allEdgeLengths.append(edges.1)
            allEdgeLengths.append(edges.2)
        }

        let minEdge = allEdgeLengths.min() ?? 0
        let maxEdge = allEdgeLengths.max() ?? 0
        let avgEdge = allEdgeLengths.reduce(0, +) / Double(allEdgeLengths.count)

        return (minEdge, maxEdge, avgEdge, allEdgeLengths.count)
    }

    /// Calculate PLA weight estimate
    /// - Parameter infill: Infill percentage (0.0 to 1.0)
    /// - Returns: Weight in grams
    func calculatePLAWeight(infill: Double = 1.0) -> Double {
        let volumeMM3 = volume()
        let volumeCM3 = volumeMM3 / 1000.0
        let plaDensity = 1.24 // g/cm³

        if infill >= 1.0 {
            // 100% infill
            return volumeCM3 * plaDensity
        } else {
            // For partial infill, use simple proportional estimate
            // More accurate methods would require actual slicer simulation
            return volumeCM3 * plaDensity * infill
        }
    }

    /// Extract all unique edges (for wireframe rendering)
    func extractEdges() -> [Edge] {
        var edgeSet = Set<Edge>()
        edgeSet.reserveCapacity(triangles.count * 3)

        for triangle in triangles {
            edgeSet.insert(Edge(triangle.v1, triangle.v2))
            edgeSet.insert(Edge(triangle.v2, triangle.v3))
            edgeSet.insert(Edge(triangle.v3, triangle.v1))
        }

        return Array(edgeSet)
    }

    /// Extract feature edges only (edges where adjacent faces have significantly different normals)
    /// - Parameter angleThreshold: Minimum angle in degrees between face normals to consider an edge a "feature edge"
    /// - Returns: Array of feature edges (sharp edges, creases, and boundary edges)
    func extractFeatureEdges(angleThreshold: Double = 30.0) -> [Edge] {
        // Build edge-to-triangles adjacency map
        var edgeTriangles: [Edge: [Triangle]] = [:]
        edgeTriangles.reserveCapacity(triangles.count * 3)

        for triangle in triangles {
            let edges = [
                Edge(triangle.v1, triangle.v2),
                Edge(triangle.v2, triangle.v3),
                Edge(triangle.v3, triangle.v1)
            ]
            for edge in edges {
                edgeTriangles[edge, default: []].append(triangle)
            }
        }

        // Convert threshold to cosine (for faster comparison)
        let thresholdRadians = angleThreshold * .pi / 180.0
        let cosThreshold = cos(thresholdRadians)

        var featureEdges: [Edge] = []
        featureEdges.reserveCapacity(edgeTriangles.count / 4) // Rough estimate

        for (edge, adjacentTriangles) in edgeTriangles {
            // Boundary edge (only one adjacent triangle) - always include
            if adjacentTriangles.count == 1 {
                featureEdges.append(edge)
                continue
            }

            // Check if any pair of adjacent faces has angle exceeding threshold
            if adjacentTriangles.count >= 2 {
                let n1 = adjacentTriangles[0].normal
                let n2 = adjacentTriangles[1].normal

                // Dot product of normals gives cos(angle between them)
                let dot = n1.dot(n2)

                // If angle > threshold (i.e., cos(angle) < cos(threshold)), it's a feature edge
                if dot < cosThreshold {
                    featureEdges.append(edge)
                }
            }
        }

        return featureEdges
    }

    /// Extract all edges with styling based on angle threshold
    /// Feature edges (>= threshold angle) get full width/opacity, soft edges (< threshold but >= minAngle) get reduced
    /// Edges below minAngle are hidden (not included)
    /// - Parameter angleThreshold: Angle in degrees; edges with angle >= this are feature edges
    /// - Parameter minAngle: Minimum angle in degrees; edges below this are hidden
    /// - Returns: Array of styled edges with width multiplier and alpha values
    func extractStyledEdges(angleThreshold: Double = 20.0, minAngle: Double = 1.0) -> [StyledEdge] {
        // Build edge-to-triangles adjacency map
        var edgeTriangles: [Edge: [Triangle]] = [:]
        edgeTriangles.reserveCapacity(triangles.count * 3)

        for triangle in triangles {
            let edges = [
                Edge(triangle.v1, triangle.v2),
                Edge(triangle.v2, triangle.v3),
                Edge(triangle.v3, triangle.v1)
            ]
            for edge in edges {
                edgeTriangles[edge, default: []].append(triangle)
            }
        }

        // Convert thresholds to cosine (for faster comparison)
        let thresholdRadians = angleThreshold * .pi / 180.0
        let cosThreshold = cos(thresholdRadians)
        let minAngleRadians = minAngle * .pi / 180.0
        let cosMinAngle = cos(minAngleRadians)

        var styledEdges: [StyledEdge] = []
        styledEdges.reserveCapacity(edgeTriangles.count)

        for (edge, adjacentTriangles) in edgeTriangles {
            // Boundary edge (only one adjacent triangle) - always a feature edge
            if adjacentTriangles.count == 1 {
                styledEdges.append(StyledEdge(edge: edge, isFeatureEdge: true))
                continue
            }

            // Check angle between adjacent faces
            if adjacentTriangles.count >= 2 {
                let n1 = adjacentTriangles[0].normal
                let n2 = adjacentTriangles[1].normal

                // Dot product of normals gives cos(angle between them)
                let dot = n1.dot(n2)

                // Skip edges with angle < minAngle (dot > cosMinAngle means angle is smaller)
                if dot > cosMinAngle {
                    continue
                }

                // If angle >= threshold (i.e., cos(angle) <= cos(threshold)), it's a feature edge
                let isFeatureEdge = dot < cosThreshold
                styledEdges.append(StyledEdge(edge: edge, isFeatureEdge: isFeatureEdge))
            }
        }

        return styledEdges
    }

    /// Calculate average vertex spacing (for adaptive selection threshold)
    func averageVertexSpacing(sampleSize: Int = 1000) -> Double {
        let samplesToCheck = min(sampleSize, triangles.count)
        guard samplesToCheck > 0 else { return 0 }

        var totalSpacing: Double = 0
        var count = 0

        for i in 0..<samplesToCheck {
            let triangle = triangles[i]
            totalSpacing += triangle.v1.distance(to: triangle.v2)
            totalSpacing += triangle.v2.distance(to: triangle.v3)
            totalSpacing += triangle.v3.distance(to: triangle.v1)
            count += 3
        }

        return totalSpacing / Double(count)
    }
}

// MARK: - StyledEdge

/// An edge with styling information for rendering (width multiplier and alpha)
struct StyledEdge {
    let edge: Edge
    let widthMultiplier: Float  // 1.0 for feature edges, smaller for soft edges
    let alpha: Float            // 1.0 for feature edges, lower for soft edges

    init(edge: Edge, isFeatureEdge: Bool) {
        self.edge = edge
        if isFeatureEdge {
            self.widthMultiplier = 1.0
            self.alpha = 1.0
        } else {
            self.widthMultiplier = 0.5  // Half width for soft edges
            self.alpha = 0.3            // More transparent for soft edges
        }
    }
}

// MARK: - Edge

/// An edge defined by two vertices (for wireframe rendering)
struct Edge: Hashable {
    let start: Vector3
    let end: Vector3

    init(_ p1: Vector3, _ p2: Vector3) {
        // Normalize edge direction to avoid duplicates
        // Always store with "smaller" vertex first (lexicographic ordering)
        if p1.x < p2.x || (p1.x == p2.x && p1.y < p2.y) || (p1.x == p2.x && p1.y == p2.y && p1.z < p2.z) {
            start = p1
            end = p2
        } else {
            start = p2
            end = p1
        }
    }

    var length: Double {
        start.distance(to: end)
    }

    func hash(into hasher: inout Hasher) {
        // Round to avoid floating point precision issues
        hasher.combine(round(start.x * 1000000) / 1000000)
        hasher.combine(round(start.y * 1000000) / 1000000)
        hasher.combine(round(start.z * 1000000) / 1000000)
        hasher.combine(round(end.x * 1000000) / 1000000)
        hasher.combine(round(end.y * 1000000) / 1000000)
        hasher.combine(round(end.z * 1000000) / 1000000)
    }

    static func == (lhs: Edge, rhs: Edge) -> Bool {
        lhs.start.isApproximatelyEqual(to: rhs.start, tolerance: 1e-6) &&
        lhs.end.isApproximatelyEqual(to: rhs.end, tolerance: 1e-6)
    }
}

// MARK: - Codable

extension STLModel: Codable {}

// MARK: - CustomStringConvertible

extension STLModel: CustomStringConvertible {
    var description: String {
        let name = self.name ?? "Unnamed"
        return "STLModel(\"\(name)\", \(triangleCount) triangles)"
    }
}
