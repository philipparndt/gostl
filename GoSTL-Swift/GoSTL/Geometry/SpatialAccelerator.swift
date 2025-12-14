import Foundation
import simd

/// Spatial acceleration structure for fast ray-triangle intersection and vertex snapping
/// Uses a BVH (Bounding Volume Hierarchy) for ray casting and a spatial grid for vertex lookup
final class SpatialAccelerator: @unchecked Sendable {

    // MARK: - BVH Node

    private final class BVHNode {
        var bounds: BoundingBox
        var left: BVHNode?
        var right: BVHNode?
        var triangleIndices: [Int]?  // Leaf nodes store triangle indices

        init(bounds: BoundingBox) {
            self.bounds = bounds
        }
    }

    // MARK: - Spatial Grid

    private struct GridCell {
        var vertices: [(position: Vector3, triangleIndex: Int)]
    }

    // MARK: - Properties

    private var bvhRoot: BVHNode?
    private let triangles: [Triangle]

    // Spatial grid for vertex snapping
    private var vertexGrid: [Int: GridCell] = [:]
    private var gridCellSize: Double = 1.0
    private var gridOrigin: Vector3 = .zero
    private var gridDimensions: (x: Int, y: Int, z: Int) = (0, 0, 0)

    // Constants
    private static let maxTrianglesPerLeaf = 8
    private static let maxDepth = 32

    // MARK: - Initialization

    init(triangles: [Triangle]) {
        self.triangles = triangles

        guard !triangles.isEmpty else { return }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Build BVH and vertex grid in parallel
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            self.buildBVH()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            self.buildVertexGrid()
            group.leave()
        }

        group.wait()

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("SpatialAccelerator built in \(String(format: "%.2f", totalTime * 1000))ms (\(triangles.count) triangles)")
    }

    // MARK: - BVH Construction

    // Depth at which to start parallel subtree construction
    private static let parallelDepthThreshold = 4

    private func buildBVH() {
        // Pre-compute all centroids in parallel for faster sorting
        var centroids = [Vector3](repeating: .zero, count: triangles.count)
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let chunkSize = max(1000, triangles.count / processorCount)

        DispatchQueue.concurrentPerform(iterations: (triangles.count + chunkSize - 1) / chunkSize) { chunkIndex in
            let startIndex = chunkIndex * chunkSize
            let endIndex = min(startIndex + chunkSize, triangles.count)
            for i in startIndex..<endIndex {
                centroids[i] = triangleCentroid(triangles[i])
            }
        }

        // Use a single indices array and operate on ranges (in-place) to avoid copying
        var indices = Array(0..<triangles.count)
        bvhRoot = buildBVHNodeInPlace(indices: &indices, range: 0..<triangles.count, centroids: centroids, depth: 0)
    }

    /// Build BVH node using in-place partitioning (no array copies!)
    private func buildBVHNodeInPlace(indices: inout [Int], range: Range<Int>, centroids: [Vector3], depth: Int) -> BVHNode? {
        guard !range.isEmpty else { return nil }

        // Calculate bounds
        let bounds: BoundingBox
        if range.count > 50000 {
            bounds = calculateBoundsInRange(indices: indices, range: range)
        } else {
            var b = triangleBounds(triangles[indices[range.lowerBound]])
            for i in (range.lowerBound + 1)..<range.upperBound {
                b.extend(triangleBounds(triangles[indices[i]]))
            }
            bounds = b
        }

        let node = BVHNode(bounds: bounds)

        // Create leaf if few enough triangles or max depth reached
        if range.count <= Self.maxTrianglesPerLeaf || depth >= Self.maxDepth {
            node.triangleIndices = Array(indices[range])
            return node
        }

        // Find split axis (longest axis of bounds)
        let size = bounds.size
        let axis: Int
        if size.x >= size.y && size.x >= size.z {
            axis = 0
        } else if size.y >= size.z {
            axis = 1
        } else {
            axis = 2
        }

        // Partition in-place using quickselect
        let mid = range.lowerBound + range.count / 2
        partialSortInPlace(indices: &indices, range: range, centroids: centroids, axis: axis, k: mid)

        let leftRange = range.lowerBound..<mid
        let rightRange = mid..<range.upperBound

        // Build subtrees - parallel at shallow depths only
        if depth < Self.parallelDepthThreshold && range.count > 10000 {
            // For parallel building, we need separate copies since we can't share mutable array
            var leftIndices = Array(indices[leftRange])
            var rightIndices = Array(indices[rightRange])

            var leftNode: BVHNode?
            var rightNode: BVHNode?

            DispatchQueue.concurrentPerform(iterations: 2) { i in
                if i == 0 {
                    leftNode = self.buildBVHNodeInPlace(indices: &leftIndices, range: 0..<leftIndices.count, centroids: centroids, depth: depth + 1)
                } else {
                    rightNode = self.buildBVHNodeInPlace(indices: &rightIndices, range: 0..<rightIndices.count, centroids: centroids, depth: depth + 1)
                }
            }

            node.left = leftNode
            node.right = rightNode
        } else {
            // Sequential construction - fully in-place, no copies
            node.left = buildBVHNodeInPlace(indices: &indices, range: leftRange, centroids: centroids, depth: depth + 1)
            node.right = buildBVHNodeInPlace(indices: &indices, range: rightRange, centroids: centroids, depth: depth + 1)
        }

        return node
    }

    /// Calculate bounds for a range of indices
    private func calculateBoundsInRange(indices: [Int], range: Range<Int>) -> BoundingBox {
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let chunkSize = max(1000, range.count / processorCount)
        let chunkCount = (range.count + chunkSize - 1) / chunkSize

        var partialBounds = [BoundingBox](repeating: BoundingBox(), count: chunkCount)

        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            let startOffset = chunkIndex * chunkSize
            let endOffset = min(startOffset + chunkSize, range.count)
            let startIndex = range.lowerBound + startOffset
            let endIndex = range.lowerBound + endOffset

            guard startIndex < endIndex else { return }

            var bounds = triangleBounds(triangles[indices[startIndex]])
            for i in (startIndex + 1)..<endIndex {
                bounds.extend(triangleBounds(triangles[indices[i]]))
            }
            partialBounds[chunkIndex] = bounds
        }

        // Merge bounds
        var finalBounds = partialBounds[0]
        for i in 1..<chunkCount {
            finalBounds.extend(partialBounds[i])
        }
        return finalBounds
    }

    /// In-place quickselect for a range
    private func partialSortInPlace(indices: inout [Int], range: Range<Int>, centroids: [Vector3], axis: Int, k: Int) {
        guard range.count > 1 else { return }

        var left = range.lowerBound
        var right = range.upperBound - 1

        while left < right {
            // Median-of-three pivot selection
            let mid = (left + right) / 2
            let pivotIndex = medianOfThreeInRange(indices: indices, centroids: centroids, axis: axis, a: left, b: mid, c: right)

            // Move pivot to end
            indices.swapAt(pivotIndex, right)
            let pivotValue = centroidValue(centroids[indices[right]], axis: axis)

            // Partition
            var storeIndex = left
            for i in left..<right {
                if centroidValue(centroids[indices[i]], axis: axis) < pivotValue {
                    indices.swapAt(i, storeIndex)
                    storeIndex += 1
                }
            }
            indices.swapAt(storeIndex, right)

            // Recurse into the partition containing k
            if storeIndex == k {
                return
            } else if k < storeIndex {
                right = storeIndex - 1
            } else {
                left = storeIndex + 1
            }
        }
    }

    @inline(__always)
    private func centroidValue(_ centroid: Vector3, axis: Int) -> Double {
        switch axis {
        case 0: return centroid.x
        case 1: return centroid.y
        default: return centroid.z
        }
    }

    private func medianOfThreeInRange(indices: [Int], centroids: [Vector3], axis: Int, a: Int, b: Int, c: Int) -> Int {
        let va = centroidValue(centroids[indices[a]], axis: axis)
        let vb = centroidValue(centroids[indices[b]], axis: axis)
        let vc = centroidValue(centroids[indices[c]], axis: axis)

        if va < vb {
            if vb < vc { return b }
            else if va < vc { return c }
            else { return a }
        } else {
            if va < vc { return a }
            else if vb < vc { return c }
            else { return b }
        }
    }

    private func triangleBounds(_ triangle: Triangle) -> BoundingBox {
        var box = BoundingBox(point: triangle.v1)
        box.extend(triangle.v2)
        box.extend(triangle.v3)
        return box
    }

    private func triangleCentroid(_ triangle: Triangle) -> Vector3 {
        (triangle.v1 + triangle.v2 + triangle.v3) / 3.0
    }

    // MARK: - Vertex Grid Construction

    private func buildVertexGrid() {
        guard !triangles.isEmpty else { return }

        // Calculate model bounds in parallel
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let chunkSize = max(1000, triangles.count / processorCount)
        let chunkCount = (triangles.count + chunkSize - 1) / chunkSize

        var partialBounds = [BoundingBox](repeating: BoundingBox(), count: chunkCount)

        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            let startIndex = chunkIndex * chunkSize
            let endIndex = min(startIndex + chunkSize, triangles.count)
            guard startIndex < endIndex else { return }

            var bounds = triangleBounds(triangles[startIndex])
            for i in (startIndex + 1)..<endIndex {
                bounds.extend(triangleBounds(triangles[i]))
            }
            partialBounds[chunkIndex] = bounds
        }

        var modelBounds = partialBounds[0]
        for i in 1..<chunkCount {
            modelBounds.extend(partialBounds[i])
        }

        // Use cell size based on model size (aim for ~100 cells per axis max)
        let size = modelBounds.size
        let maxDim = max(size.x, size.y, size.z)
        gridCellSize = max(maxDim / 100.0, 0.1)  // At least 0.1mm cells
        gridOrigin = modelBounds.min

        gridDimensions = (
            x: Int(ceil(size.x / gridCellSize)) + 1,
            y: Int(ceil(size.y / gridCellSize)) + 1,
            z: Int(ceil(size.z / gridCellSize)) + 1
        )

        // Build partial grids in parallel, then merge
        var partialGrids = [[Int: GridCell]](repeating: [:], count: chunkCount)
        var partialSeenSets = [Set<Int>](repeating: Set<Int>(), count: chunkCount)

        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            let startIndex = chunkIndex * chunkSize
            let endIndex = min(startIndex + chunkSize, triangles.count)

            var localGrid: [Int: GridCell] = [:]
            var localSeen = Set<Int>()

            for triangleIndex in startIndex..<endIndex {
                let triangle = triangles[triangleIndex]
                for vertex in [triangle.v1, triangle.v2, triangle.v3] {
                    let hash = vertexHash(vertex)
                    if localSeen.contains(hash) {
                        continue
                    }
                    localSeen.insert(hash)

                    let cellKey = gridKeyLocal(for: vertex)
                    if localGrid[cellKey] == nil {
                        localGrid[cellKey] = GridCell(vertices: [])
                    }
                    localGrid[cellKey]?.vertices.append((position: vertex, triangleIndex: triangleIndex))
                }
            }

            partialGrids[chunkIndex] = localGrid
            partialSeenSets[chunkIndex] = localSeen
        }

        // Merge partial grids (sequential, but faster than building sequentially)
        var globalSeen = Set<Int>()
        for chunkIndex in 0..<chunkCount {
            for (cellKey, cell) in partialGrids[chunkIndex] {
                for (vertex, triangleIndex) in cell.vertices {
                    let hash = vertexHash(vertex)
                    if globalSeen.contains(hash) {
                        continue
                    }
                    globalSeen.insert(hash)

                    if vertexGrid[cellKey] == nil {
                        vertexGrid[cellKey] = GridCell(vertices: [])
                    }
                    vertexGrid[cellKey]?.vertices.append((position: vertex, triangleIndex: triangleIndex))
                }
            }
        }
    }

    /// Grid key calculation that doesn't depend on instance state (for parallel use)
    private func gridKeyLocal(for point: Vector3) -> Int {
        let ix = Int((point.x - gridOrigin.x) / gridCellSize)
        let iy = Int((point.y - gridOrigin.y) / gridCellSize)
        let iz = Int((point.z - gridOrigin.z) / gridCellSize)
        let cx = max(0, min(ix, gridDimensions.x - 1))
        let cy = max(0, min(iy, gridDimensions.y - 1))
        let cz = max(0, min(iz, gridDimensions.z - 1))
        return cx + cy * gridDimensions.x + cz * gridDimensions.x * gridDimensions.y
    }

    private func vertexHash(_ v: Vector3) -> Int {
        // Round to avoid floating point precision issues (1 micron precision)
        let scale = 1000.0
        let x = Int(round(v.x * scale))
        let y = Int(round(v.y * scale))
        let z = Int(round(v.z * scale))
        var hasher = Hasher()
        hasher.combine(x)
        hasher.combine(y)
        hasher.combine(z)
        return hasher.finalize()
    }

    private func gridKey(for point: Vector3) -> Int {
        let ix = Int((point.x - gridOrigin.x) / gridCellSize)
        let iy = Int((point.y - gridOrigin.y) / gridCellSize)
        let iz = Int((point.z - gridOrigin.z) / gridCellSize)
        // Clamp to valid range
        let cx = max(0, min(ix, gridDimensions.x - 1))
        let cy = max(0, min(iy, gridDimensions.y - 1))
        let cz = max(0, min(iz, gridDimensions.z - 1))
        return cx + cy * gridDimensions.x + cz * gridDimensions.x * gridDimensions.y
    }

    // MARK: - Ray Casting

    /// Find the closest intersection of a ray with the model
    /// Returns the triangle index and intersection point, or nil if no hit
    func raycast(ray: Ray) -> (triangleIndex: Int, position: Vector3, normal: Vector3, distance: Float)? {
        guard let root = bvhRoot else { return nil }

        var closestHit: (triangleIndex: Int, position: Vector3, normal: Vector3, distance: Float)?
        var closestDistance: Float = .infinity

        raycastNode(node: root, ray: ray, closestHit: &closestHit, closestDistance: &closestDistance)

        return closestHit
    }

    private func raycastNode(
        node: BVHNode,
        ray: Ray,
        closestHit: inout (triangleIndex: Int, position: Vector3, normal: Vector3, distance: Float)?,
        closestDistance: inout Float
    ) {
        // Test ray against node bounds
        guard let (tMin, tMax) = rayBoxIntersection(ray: ray, box: node.bounds),
              tMin < closestDistance && tMax >= 0 else {
            return
        }

        // Leaf node - test triangles
        if let indices = node.triangleIndices {
            for index in indices {
                let triangle = triangles[index]
                if let (position, normal) = triangle.intersectionPoint(ray: ray) {
                    let distance = ray.origin.distance(to: position.float3)
                    if distance < closestDistance {
                        closestDistance = distance
                        closestHit = (index, position, normal, distance)
                    }
                }
            }
            return
        }

        // Interior node - recurse into children
        // Visit closer child first for better early termination
        if let left = node.left, let right = node.right {
            let leftDist = rayBoxDistance(ray: ray, box: left.bounds)
            let rightDist = rayBoxDistance(ray: ray, box: right.bounds)

            if leftDist < rightDist {
                raycastNode(node: left, ray: ray, closestHit: &closestHit, closestDistance: &closestDistance)
                raycastNode(node: right, ray: ray, closestHit: &closestHit, closestDistance: &closestDistance)
            } else {
                raycastNode(node: right, ray: ray, closestHit: &closestHit, closestDistance: &closestDistance)
                raycastNode(node: left, ray: ray, closestHit: &closestHit, closestDistance: &closestDistance)
            }
        } else {
            if let left = node.left {
                raycastNode(node: left, ray: ray, closestHit: &closestHit, closestDistance: &closestDistance)
            }
            if let right = node.right {
                raycastNode(node: right, ray: ray, closestHit: &closestHit, closestDistance: &closestDistance)
            }
        }
    }

    /// Ray-AABB intersection test (slab method)
    /// Returns (tMin, tMax) if intersection, nil otherwise
    private func rayBoxIntersection(ray: Ray, box: BoundingBox) -> (Float, Float)? {
        let invDir = SIMD3<Float>(
            ray.direction.x != 0 ? 1.0 / ray.direction.x : .infinity,
            ray.direction.y != 0 ? 1.0 / ray.direction.y : .infinity,
            ray.direction.z != 0 ? 1.0 / ray.direction.z : .infinity
        )

        let boxMin = SIMD3<Float>(Float(box.min.x), Float(box.min.y), Float(box.min.z))
        let boxMax = SIMD3<Float>(Float(box.max.x), Float(box.max.y), Float(box.max.z))

        let t1 = (boxMin - ray.origin) * invDir
        let t2 = (boxMax - ray.origin) * invDir

        let tMin = simd_min(t1, t2)
        let tMax = simd_max(t1, t2)

        let tNear = max(max(tMin.x, tMin.y), tMin.z)
        let tFar = min(min(tMax.x, tMax.y), tMax.z)

        if tNear > tFar || tFar < 0 {
            return nil
        }

        return (tNear, tFar)
    }

    /// Distance to box entry point (for sorting children)
    private func rayBoxDistance(ray: Ray, box: BoundingBox) -> Float {
        if let (tMin, _) = rayBoxIntersection(ray: ray, box: box) {
            return max(tMin, 0)
        }
        return .infinity
    }

    // MARK: - Vertex Snapping

    /// Find the closest vertex to a point within a given radius
    /// Uses spatial grid for O(1) lookup instead of O(n) full scan
    func findClosestVertex(to point: Vector3, maxDistance: Double) -> Vector3? {
        // Calculate how many cells to search based on maxDistance
        let cellRadius = Int(ceil(maxDistance / gridCellSize))

        let centerCell = (
            x: Int((point.x - gridOrigin.x) / gridCellSize),
            y: Int((point.y - gridOrigin.y) / gridCellSize),
            z: Int((point.z - gridOrigin.z) / gridCellSize)
        )

        var closestVertex: Vector3?
        var closestDistance = maxDistance

        // Search neighboring cells
        for dx in -cellRadius...cellRadius {
            for dy in -cellRadius...cellRadius {
                for dz in -cellRadius...cellRadius {
                    let cx = centerCell.x + dx
                    let cy = centerCell.y + dy
                    let cz = centerCell.z + dz

                    // Skip if outside grid
                    guard cx >= 0 && cx < gridDimensions.x &&
                          cy >= 0 && cy < gridDimensions.y &&
                          cz >= 0 && cz < gridDimensions.z else {
                        continue
                    }

                    let key = cx + cy * gridDimensions.x + cz * gridDimensions.x * gridDimensions.y
                    guard let cell = vertexGrid[key] else { continue }

                    for (vertex, _) in cell.vertices {
                        let dist = vertex.distance(to: point)
                        if dist < closestDistance {
                            closestDistance = dist
                            closestVertex = vertex
                        }
                    }
                }
            }
        }

        return closestVertex
    }

    // MARK: - Triangle Lookup

    /// Find which triangle a ray intersects (returns index only)
    func findTriangleAtRay(ray: Ray) -> Int? {
        raycast(ray: ray)?.triangleIndex
    }
}

