import Foundation
import simd

/// Utilities for ray-based point picking on 3D models
struct RayPicking {
    /// Find intersection point on model for a ray with vertex snapping
    /// Uses spatial accelerator for O(log n) performance when available
    ///
    /// - Parameters:
    ///   - ray: The ray to cast
    ///   - model: The model to test against
    ///   - accelerator: Optional spatial accelerator for fast ray casting
    ///   - snap: Which nearby vertex the click means, judged on screen so that
    ///     model scale and zoom do not change how it feels
    /// - Returns: The intersection position (snapped to vertex if nearby), or nil if no intersection
    static func findIntersection(
        ray: Ray,
        model: STLModel,
        accelerator: SpatialAccelerator? = nil,
        snap: ScreenSnap
    ) -> Vector3? {
        // Use accelerator for fast ray casting if available
        if let accelerator = accelerator {
            guard let hit = accelerator.raycast(ray: ray) else {
                return nil
            }

            // Collect the vertices around the hit, then let the cursor decide
            var candidates: [Vector3] = []
            accelerator.forEachVertex(
                near: hit.position,
                maxDistance: snap.searchRadius(atDepth: Double(hit.distance))
            ) { candidates.append($0) }

            return snap.nearest(of: candidates) ?? hit.position
        }

        // Fallback to O(n) algorithm
        var closestDistance: Float = .infinity
        var closestIntersection: Vector3?

        // Test all triangles to find the closest hit point
        for triangle in model.triangles {
            if let (position, _) = triangle.intersectionPoint(ray: ray) {
                let distance = ray.origin.distance(to: position.float3)
                if distance < closestDistance {
                    closestDistance = distance
                    closestIntersection = position
                }
            }
        }

        guard let intersection = closestIntersection else {
            return nil
        }

        // Snap to the vertex nearest the cursor, out of those near the hit
        let reach = snap.searchRadius(atDepth: Double(closestDistance))
        let candidates = model.triangles
            .flatMap { [$0.v1, $0.v2, $0.v3] }
            .filter { $0.distance(to: intersection) <= reach }

        return snap.nearest(of: candidates) ?? intersection
    }

    /// Find intersection point on model with full MeasurementPoint information
    /// Uses spatial accelerator for O(log n) performance when available
    ///
    /// - Parameters:
    ///   - ray: The ray to cast
    ///   - model: The model to test against
    ///   - accelerator: Optional spatial accelerator for fast ray casting
    ///   - snapThreshold: Distance threshold for snapping to vertices (default 2.0)
    /// - Returns: MeasurementPoint with position and normal, or nil if no intersection
    static func findMeasurementPoint(
        ray: Ray,
        model: STLModel,
        accelerator: SpatialAccelerator? = nil,
        snapThreshold: Double = 2.0
    ) -> MeasurementPoint? {
        // Use accelerator for fast ray casting if available
        if let accelerator = accelerator {
            guard let hit = accelerator.raycast(ray: ray) else {
                return nil
            }

            // Use spatial grid for fast vertex snapping
            let snappedPosition = accelerator.findClosestVertex(to: hit.position, maxDistance: snapThreshold) ?? hit.position
            return MeasurementPoint(position: snappedPosition, normal: hit.normal)
        }

        // Fallback to O(n) algorithm
        var closestDistance: Float = .infinity
        var closestIntersection: (position: Vector3, normal: Vector3)?

        // Test all triangles to find the closest hit point
        for triangle in model.triangles {
            if let (position, normal) = triangle.intersectionPoint(ray: ray) {
                let distance = ray.origin.distance(to: position.float3)
                if distance < closestDistance {
                    closestDistance = distance
                    closestIntersection = (position, normal)
                }
            }
        }

        guard let intersection = closestIntersection else {
            return nil
        }

        // Snap to nearest vertex in the model if within threshold
        var snappedPosition = intersection.position
        var closestVertexDistance: Double = .infinity

        for triangle in model.triangles {
            for vertex in [triangle.v1, triangle.v2, triangle.v3] {
                let distance = vertex.distance(to: intersection.position)
                if distance < closestVertexDistance && distance <= snapThreshold {
                    closestVertexDistance = distance
                    snappedPosition = vertex
                }
            }
        }

        return MeasurementPoint(position: snappedPosition, normal: intersection.normal)
    }
}

