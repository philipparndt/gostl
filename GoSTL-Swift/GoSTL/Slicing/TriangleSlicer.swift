import Foundation
import os.signpost

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
    private static let log = OSLog(subsystem: "com.gostl.app", category: "slicing")

    /// Slice a set of triangles against the current slice bounds
    static func sliceTriangles(_ triangles: [Triangle], bounds: [[Double]]) -> SlicedTriangles {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Use parallel processing for large triangle counts
        let useParallel = triangles.count > 1000
        let chunkSize = max(500, triangles.count / ProcessInfo.processInfo.activeProcessorCount)

        if useParallel {
            return sliceTrianglesParallel(triangles, bounds: bounds, chunkSize: chunkSize, startTime: startTime)
        } else {
            return sliceTrianglesSerial(triangles, bounds: bounds, startTime: startTime)
        }
    }

    /// Serial implementation for small triangle counts
    private static func sliceTrianglesSerial(_ triangles: [Triangle], bounds: [[Double]], startTime: CFAbsoluteTime) -> SlicedTriangles {
        var resultTriangles: [Triangle] = []
        var cutEdges: [CutEdge] = []

        var fullyInsideCount = 0
        var fullyOutsideCount = 0
        var clippedCount = 0

        for triangle in triangles {
            let result = sliceSingleTriangle(triangle, bounds: bounds)
            switch result {
            case .inside:
                fullyInsideCount += 1
                resultTriangles.append(triangle)
            case .outside:
                fullyOutsideCount += 1
            case .clipped(let tris, let edges):
                clippedCount += 1
                resultTriangles.append(contentsOf: tris)
                cutEdges.append(contentsOf: edges)
            }
        }

        // Clip cut edges to bounds
        let clippedCutEdges = cutEdges.compactMap { edge -> CutEdge? in
            clipCutEdgeToBounds(edge, bounds: bounds)
        }

        return SlicedTriangles(triangles: resultTriangles, cutEdges: clippedCutEdges)
    }

    /// Container for chunk results (class for reference semantics in concurrent code)
    /// @unchecked Sendable is safe because each chunk index is only accessed by one thread
    private final class ChunkResult: @unchecked Sendable {
        var triangles: [Triangle] = []
        var cutEdges: [CutEdge] = []
        var inside: Int = 0
        var outside: Int = 0
        var clipped: Int = 0
    }

    /// Parallel implementation for large triangle counts
    private static func sliceTrianglesParallel(_ triangles: [Triangle], bounds: [[Double]], chunkSize: Int, startTime: CFAbsoluteTime) -> SlicedTriangles {
        let chunkCount = (triangles.count + chunkSize - 1) / chunkSize

        // Pre-allocate result containers (each chunk writes to its own instance)
        let chunkResults = (0..<chunkCount).map { _ in ChunkResult() }

        // Process chunks in parallel
        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            let startIdx = chunkIndex * chunkSize
            let endIdx = min(startIdx + chunkSize, triangles.count)
            let result = chunkResults[chunkIndex]

            for i in startIdx..<endIdx {
                let sliceResult = sliceSingleTriangle(triangles[i], bounds: bounds)
                switch sliceResult {
                case .inside:
                    result.inside += 1
                    result.triangles.append(triangles[i])
                case .outside:
                    result.outside += 1
                case .clipped(let tris, let edges):
                    result.clipped += 1
                    result.triangles.append(contentsOf: tris)
                    result.cutEdges.append(contentsOf: edges)
                }
            }
        }

        // Merge results
        var resultTriangles: [Triangle] = []
        var cutEdges: [CutEdge] = []
        var fullyInsideCount = 0
        var fullyOutsideCount = 0
        var clippedCount = 0

        for result in chunkResults {
            resultTriangles.append(contentsOf: result.triangles)
            cutEdges.append(contentsOf: result.cutEdges)
            fullyInsideCount += result.inside
            fullyOutsideCount += result.outside
            clippedCount += result.clipped
        }

        // Clip cut edges to bounds
        let clippedCutEdges = cutEdges.compactMap { edge -> CutEdge? in
            clipCutEdgeToBounds(edge, bounds: bounds)
        }

        return SlicedTriangles(triangles: resultTriangles, cutEdges: clippedCutEdges)
    }

    /// Result of slicing a single triangle
    private enum SingleTriangleResult {
        case inside
        case outside
        case clipped(triangles: [Triangle], cutEdges: [CutEdge])
    }

    /// Slice a single triangle against all bounds (optimized with unrolled checks)
    @inline(__always)
    private static func sliceSingleTriangle(_ triangle: Triangle, bounds: [[Double]]) -> SingleTriangleResult {
        // Direct vertex access (avoid array allocation)
        let v1 = triangle.v1
        let v2 = triangle.v2
        let v3 = triangle.v3

        // Extract bounds once (avoid repeated array access)
        let xMin = bounds[0][0], xMax = bounds[0][1]
        let yMin = bounds[1][0], yMax = bounds[1][1]
        let zMin = bounds[2][0], zMax = bounds[2][1]

        // Unrolled bounding box rejection test for X axis
        let x1 = v1.x, x2 = v2.x, x3 = v3.x
        if x1 < xMin && x2 < xMin && x3 < xMin { return .outside }
        if x1 > xMax && x2 > xMax && x3 > xMax { return .outside }

        // Unrolled bounding box rejection test for Y axis
        let y1 = v1.y, y2 = v2.y, y3 = v3.y
        if y1 < yMin && y2 < yMin && y3 < yMin { return .outside }
        if y1 > yMax && y2 > yMax && y3 > yMax { return .outside }

        // Unrolled bounding box rejection test for Z axis
        let z1 = v1.z, z2 = v2.z, z3 = v3.z
        if z1 < zMin && z2 < zMin && z3 < zMin { return .outside }
        if z1 > zMax && z2 > zMax && z3 > zMax { return .outside }

        // Check if fully inside (all vertices within bounds)
        let v1Inside = x1 >= xMin && x1 <= xMax && y1 >= yMin && y1 <= yMax && z1 >= zMin && z1 <= zMax
        let v2Inside = x2 >= xMin && x2 <= xMax && y2 >= yMin && y2 <= yMax && z2 >= zMin && z2 <= zMax
        let v3Inside = x3 >= xMin && x3 <= xMax && y3 >= yMin && y3 <= yMax && z3 >= zMin && z3 <= zMax

        if v1Inside && v2Inside && v3Inside {
            return .inside
        }

        // Need to clip - start with the original triangle
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
                    keepPositiveSide: true
                )
                nextTriangles.append(contentsOf: result.triangles)
                nextCutEdges.append(contentsOf: result.cutEdges)
            }

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
                    keepPositiveSide: false
                )
                nextTriangles.append(contentsOf: result.triangles)
                nextCutEdges.append(contentsOf: result.cutEdges)
            }

            currentCutEdges.append(contentsOf: nextCutEdges)
            currentTriangles = nextTriangles
        }

        return .clipped(triangles: currentTriangles, cutEdges: currentCutEdges)
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

    /// Clip a single triangle against an axis-aligned plane (optimized - no array allocations)
    @inline(__always)
    private static func clipTriangleToPlane(
        _ triangle: Triangle,
        axis: Int,
        planePosition: Double,
        keepPositiveSide: Bool
    ) -> SlicedTriangles {
        let v1 = triangle.v1
        let v2 = triangle.v2
        let v3 = triangle.v3

        // Get signed distances from plane for each vertex (inline, no array)
        let c1 = v1.component(axis: axis)
        let c2 = v2.component(axis: axis)
        let c3 = v3.component(axis: axis)

        let d1 = keepPositiveSide ? (c1 - planePosition) : (planePosition - c1)
        let d2 = keepPositiveSide ? (c2 - planePosition) : (planePosition - c2)
        let d3 = keepPositiveSide ? (c3 - planePosition) : (planePosition - c3)

        // Check which vertices are on positive side
        let p1 = d1 >= 0
        let p2 = d2 >= 0
        let p3 = d3 >= 0

        // Count positive vertices
        let positiveCount = (p1 ? 1 : 0) + (p2 ? 1 : 0) + (p3 ? 1 : 0)

        // All vertices on positive side - keep entire triangle
        if positiveCount == 3 {
            return SlicedTriangles(triangles: [triangle], cutEdges: [])
        }

        // All vertices on negative side - discard triangle
        if positiveCount == 0 {
            return SlicedTriangles(triangles: [], cutEdges: [])
        }

        // Triangle intersects plane - need to clip
        if positiveCount == 1 {
            // One vertex on positive side, two on negative
            let (v_keep, v_discard1, v_discard2): (Vector3, Vector3, Vector3)
            if p1 {
                v_keep = v1; v_discard1 = v2; v_discard2 = v3
            } else if p2 {
                v_keep = v2; v_discard1 = v1; v_discard2 = v3
            } else {
                v_keep = v3; v_discard1 = v1; v_discard2 = v2
            }

            // Find intersection points
            let intersect1 = intersectEdgeWithPlaneFast(v_keep, v_discard1, axis: axis, planePosition: planePosition)
            let intersect2 = intersectEdgeWithPlaneFast(v_keep, v_discard2, axis: axis, planePosition: planePosition)

            // Create new triangle (preserve original normal for consistent coloring)
            let newTriangle = Triangle(v1: v_keep, v2: intersect1, v3: intersect2, normal: triangle.normal)
            let cutEdge = CutEdge(start: intersect1, end: intersect2, axis: axis)

            return SlicedTriangles(triangles: [newTriangle], cutEdges: [cutEdge])

        } else {
            // Two vertices on positive side, one on negative
            let (v_discard, v_keep1, v_keep2): (Vector3, Vector3, Vector3)
            if !p1 {
                v_discard = v1; v_keep1 = v2; v_keep2 = v3
            } else if !p2 {
                v_discard = v2; v_keep1 = v1; v_keep2 = v3
            } else {
                v_discard = v3; v_keep1 = v1; v_keep2 = v2
            }

            // Find intersection points
            let intersect1 = intersectEdgeWithPlaneFast(v_keep1, v_discard, axis: axis, planePosition: planePosition)
            let intersect2 = intersectEdgeWithPlaneFast(v_keep2, v_discard, axis: axis, planePosition: planePosition)

            // Create two triangles forming a quad (preserve original normal for consistent coloring)
            let tri1 = Triangle(v1: v_keep1, v2: v_keep2, v3: intersect1, normal: triangle.normal)
            let tri2 = Triangle(v1: v_keep2, v2: intersect2, v3: intersect1, normal: triangle.normal)
            let cutEdge = CutEdge(start: intersect1, end: intersect2, axis: axis)

            return SlicedTriangles(triangles: [tri1, tri2], cutEdges: [cutEdge])
        }
    }

    /// Fast edge-plane intersection (returns only point, not t parameter)
    @inline(__always)
    private static func intersectEdgeWithPlaneFast(
        _ start: Vector3,
        _ end: Vector3,
        axis: Int,
        planePosition: Double
    ) -> Vector3 {
        let startCoord = start.component(axis: axis)
        let endCoord = end.component(axis: axis)
        let t = (planePosition - startCoord) / (endCoord - startCoord)
        let tClamped = max(0.0, min(1.0, t))

        return Vector3(
            start.x + tClamped * (end.x - start.x),
            start.y + tClamped * (end.y - start.y),
            start.z + tClamped * (end.z - start.z)
        )
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
