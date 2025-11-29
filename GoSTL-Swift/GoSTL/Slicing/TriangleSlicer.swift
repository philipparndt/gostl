import Foundation

/// Result of slicing a triangle against planes
struct SlicedTriangles {
    /// Triangles that remain after slicing
    let triangles: [Triangle]

    /// Cut edges (for visualization in axis colors)
    let cutEdges: [CutEdge]
}

/// An edge created by slicing, with its axis information for coloring
struct CutEdge {
    let start: Vector3
    let end: Vector3
    let axis: Int  // 0=X, 1=Y, 2=Z
}

/// Handles triangle clipping/splitting against axis-aligned planes
final class TriangleSlicer {

    /// Slice a set of triangles against the current slice bounds
    static func sliceTriangles(_ triangles: [Triangle], bounds: [[Double]]) -> SlicedTriangles {
        var resultTriangles: [Triangle] = []
        var cutEdges: [CutEdge] = []

        for triangle in triangles {
            let vertices = [triangle.v1, triangle.v2, triangle.v3]

            // Early exit: if triangle is completely inside bounds, no clipping needed
            var fullyInside = true
            var fullyOutside = false

            for axis in 0..<3 {
                let minBound = bounds[axis][0]
                let maxBound = bounds[axis][1]

                var allBeforeMin = true
                var allAfterMax = true
                var allInside = true

                for vertex in vertices {
                    let coord = vertex.component(axis: axis)
                    if coord >= minBound { allBeforeMin = false }
                    if coord <= maxBound { allAfterMax = false }
                    if coord < minBound || coord > maxBound { allInside = false }
                }

                // All vertices outside on same side of this axis - discard triangle
                if allBeforeMin || allAfterMax {
                    fullyOutside = true
                    break
                }

                if !allInside {
                    fullyInside = false
                }
            }

            // Triangle is fully outside - discard immediately
            if fullyOutside {
                continue
            }

            // Triangle is fully inside - keep as-is, no clipping needed
            if fullyInside {
                resultTriangles.append(triangle)
                continue
            }

            // Start with the original triangle
            var currentTriangles = [triangle]
            var currentCutEdges: [CutEdge] = []

            // Clip against all 6 planes (min and max for each axis)
            for axis in 0..<3 {
                var nextTriangles: [Triangle] = []
                var nextCutEdges: [CutEdge] = []

                // Clip against min plane
                for tri in currentTriangles {
                    let result = clipTriangleToPlane(
                        tri,
                        axis: axis,
                        planePosition: bounds[axis][0],
                        keepPositiveSide: true  // Keep side where coord > planePosition
                    )
                    nextTriangles.append(contentsOf: result.triangles)
                    nextCutEdges.append(contentsOf: result.cutEdges)
                }

                // Accumulate min plane cut edges before moving on
                currentCutEdges.append(contentsOf: nextCutEdges)
                currentTriangles = nextTriangles
                nextTriangles = []
                nextCutEdges = []

                // Clip against max plane
                for tri in currentTriangles {
                    let result = clipTriangleToPlane(
                        tri,
                        axis: axis,
                        planePosition: bounds[axis][1],
                        keepPositiveSide: false  // Keep side where coord < planePosition
                    )
                    nextTriangles.append(contentsOf: result.triangles)
                    nextCutEdges.append(contentsOf: result.cutEdges)
                }

                // Accumulate max plane cut edges
                currentCutEdges.append(contentsOf: nextCutEdges)
                currentTriangles = nextTriangles
            }

            resultTriangles.append(contentsOf: currentTriangles)
            cutEdges.append(contentsOf: currentCutEdges)
        }

        // Clip cut edges to bounds (e.g., X-axis cut edges should be clipped by Y and Z bounds)
        let clippedCutEdges = cutEdges.compactMap { edge -> CutEdge? in
            clipCutEdgeToBounds(edge, bounds: bounds)
        }

        return SlicedTriangles(triangles: resultTriangles, cutEdges: clippedCutEdges)
    }

    /// Clip a cut edge to the bounds, excluding its own axis
    /// For example, an X-axis cut edge should be clipped by Y and Z bounds
    private static func clipCutEdgeToBounds(_ edge: CutEdge, bounds: [[Double]]) -> CutEdge? {
        var p1 = edge.start
        var p2 = edge.end
        let axis = edge.axis

        // Clip against the OTHER axes (not the edge's own axis)
        for otherAxis in 0..<3 {
            if otherAxis == axis { continue }  // Skip the edge's own axis

            let minBound = bounds[otherAxis][0]
            let maxBound = bounds[otherAxis][1]

            let coord1 = p1.component(axis: otherAxis)
            let coord2 = p2.component(axis: otherAxis)

            // Both points outside on same side - edge is completely clipped
            if (coord1 < minBound && coord2 < minBound) || (coord1 > maxBound && coord2 > maxBound) {
                return nil
            }

            // Clip against min bound
            if coord1 < minBound {
                let t = (minBound - coord1) / (coord2 - coord1)
                p1 = interpolate(p1, p2, t: t)
            } else if coord2 < minBound {
                let t = (minBound - coord1) / (coord2 - coord1)
                p2 = interpolate(p1, p2, t: t)
            }

            // Clip against max bound
            let newCoord1 = p1.component(axis: otherAxis)
            let newCoord2 = p2.component(axis: otherAxis)

            if newCoord1 > maxBound {
                let t = (maxBound - newCoord1) / (newCoord2 - newCoord1)
                p1 = interpolate(p1, p2, t: t)
            } else if newCoord2 > maxBound {
                let t = (maxBound - newCoord1) / (newCoord2 - newCoord1)
                p2 = interpolate(p1, p2, t: t)
            }
        }

        return CutEdge(start: p1, end: p2, axis: axis)
    }

    /// Interpolate between two points
    private static func interpolate(_ p1: Vector3, _ p2: Vector3, t: Double) -> Vector3 {
        return Vector3(
            p1.x + t * (p2.x - p1.x),
            p1.y + t * (p2.y - p1.y),
            p1.z + t * (p2.z - p1.z)
        )
    }

    /// Clip a single triangle against an axis-aligned plane
    private static func clipTriangleToPlane(
        _ triangle: Triangle,
        axis: Int,
        planePosition: Double,
        keepPositiveSide: Bool
    ) -> SlicedTriangles {
        let vertices = [triangle.v1, triangle.v2, triangle.v3]

        // Get signed distances from plane for each vertex
        let distances = vertices.map { vertex -> Double in
            let coord = vertex.component(axis: axis)
            let dist = coord - planePosition
            return keepPositiveSide ? dist : -dist
        }

        // Count vertices on positive side (the side we want to keep)
        let positiveSide = distances.map { $0 >= 0 }
        let positiveCount = positiveSide.filter { $0 }.count

        // All vertices on positive side - keep entire triangle
        if positiveCount == 3 {
            return SlicedTriangles(triangles: [triangle], cutEdges: [])
        }

        // All vertices on negative side - discard triangle
        if positiveCount == 0 {
            return SlicedTriangles(triangles: [], cutEdges: [])
        }

        // Triangle intersects plane - need to clip
        var resultTriangles: [Triangle] = []
        var cutEdges: [CutEdge] = []

        if positiveCount == 1 {
            // One vertex on positive side, two on negative
            // Result: one smaller triangle
            let keepIndex = positiveSide.firstIndex(of: true)!
            let discardIndices = (0..<3).filter { !positiveSide[$0] }

            let v_keep = vertices[keepIndex]
            let v_discard1 = vertices[discardIndices[0]]
            let v_discard2 = vertices[discardIndices[1]]

            // Find intersection points
            let (intersect1, _) = intersectEdgeWithPlane(v_keep, v_discard1, axis: axis, planePosition: planePosition)
            let (intersect2, _) = intersectEdgeWithPlane(v_keep, v_discard2, axis: axis, planePosition: planePosition)

            // Create new triangle (preserve original normal for consistent coloring)
            let newTriangle = Triangle(v1: v_keep, v2: intersect1, v3: intersect2, normal: triangle.normal)
            resultTriangles.append(newTriangle)

            // Add cut edge
            let cutEdge = CutEdge(start: intersect1, end: intersect2, axis: axis)
            cutEdges.append(cutEdge)

        } else if positiveCount == 2 {
            // Two vertices on positive side, one on negative
            // Result: a quad (split into two triangles)
            let discardIndex = positiveSide.firstIndex(of: false)!
            let keepIndices = (0..<3).filter { positiveSide[$0] }

            let v_discard = vertices[discardIndex]
            let v_keep1 = vertices[keepIndices[0]]
            let v_keep2 = vertices[keepIndices[1]]

            // Find intersection points
            let (intersect1, _) = intersectEdgeWithPlane(v_keep1, v_discard, axis: axis, planePosition: planePosition)
            let (intersect2, _) = intersectEdgeWithPlane(v_keep2, v_discard, axis: axis, planePosition: planePosition)

            // Create two triangles forming a quad (preserve original normal for consistent coloring)
            let tri1 = Triangle(v1: v_keep1, v2: v_keep2, v3: intersect1, normal: triangle.normal)
            let tri2 = Triangle(v1: v_keep2, v2: intersect2, v3: intersect1, normal: triangle.normal)
            resultTriangles.append(tri1)
            resultTriangles.append(tri2)

            // Add cut edge
            let cutEdge = CutEdge(start: intersect1, end: intersect2, axis: axis)
            cutEdges.append(cutEdge)
        }

        return SlicedTriangles(triangles: resultTriangles, cutEdges: cutEdges)
    }

    /// Find intersection point where an edge crosses an axis-aligned plane
    /// Returns (intersection point, parameter t where 0=start, 1=end)
    private static func intersectEdgeWithPlane(
        _ start: Vector3,
        _ end: Vector3,
        axis: Int,
        planePosition: Double
    ) -> (Vector3, Double) {
        let startCoord = start.component(axis: axis)
        let endCoord = end.component(axis: axis)

        // Parametric: p(t) = start + t * (end - start)
        // Solve for t where p(t)[axis] = planePosition
        let t = (planePosition - startCoord) / (endCoord - startCoord)

        // Clamp t to [0, 1] for safety
        let tClamped = max(0.0, min(1.0, t))

        // Interpolate position
        let intersection = Vector3(
            start.x + tClamped * (end.x - start.x),
            start.y + tClamped * (end.y - start.y),
            start.z + tClamped * (end.z - start.z)
        )

        return (intersection, tClamped)
    }
}

/// Extension to get axis component from Vector3
extension Vector3 {
    func component(axis: Int) -> Double {
        switch axis {
        case 0: return x
        case 1: return y
        case 2: return z
        default: fatalError("Invalid axis: \(axis)")
        }
    }
}
