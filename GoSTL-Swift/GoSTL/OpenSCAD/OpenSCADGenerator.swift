import Foundation
import AppKit

/// Generates OpenSCAD code from measurements and triangles
class OpenSCADGenerator {

    /// Generate OpenSCAD code from selected triangles
    /// - Parameters:
    ///   - triangles: Array of triangles to convert
    ///   - indices: Optional set of indices to include (nil = all triangles)
    ///   - closeMesh: If true, detect open edges and add faces to close the mesh
    /// - Returns: OpenSCAD code string
    static func generate(from triangles: [Triangle], indices: Set<Int>? = nil, closeMesh: Bool = false) -> String {
        let selectedTriangles: [Triangle]
        if let indices = indices {
            selectedTriangles = indices.sorted().compactMap { index in
                index < triangles.count ? triangles[index] : nil
            }
        } else {
            selectedTriangles = triangles
        }

        guard !selectedTriangles.isEmpty else {
            return "// No triangles selected"
        }

        var lines: [String] = []
        lines.append("// OpenSCAD polyhedron generated from GoSTL")
        lines.append("// Generated: \(formattedDate())")
        lines.append("// Triangles: \(selectedTriangles.count)")
        if closeMesh {
            lines.append("// Mode: Closed mesh (open edges filled)")
        }
        lines.append("")

        // Extract unique points and build face indices
        var uniquePoints: [Vector3] = []
        var faces: [[Int]] = []

        for triangle in selectedTriangles {
            let idx1 = findOrAddPoint(triangle.v1, in: &uniquePoints)
            let idx2 = findOrAddPoint(triangle.v2, in: &uniquePoints)
            let idx3 = findOrAddPoint(triangle.v3, in: &uniquePoints)
            faces.append([idx1, idx2, idx3])
        }

        // If closeMesh is enabled, find open edges and create closing faces
        if closeMesh {
            let closingFaces = generateClosingFaces(points: uniquePoints, existingFaces: faces)
            if !closingFaces.isEmpty {
                lines.append("// Added \(closingFaces.count) closing face(s) to fill open edges")
                lines.append("")
                faces.append(contentsOf: closingFaces)
            }
        }

        lines.append("// \(uniquePoints.count) unique vertices, \(faces.count) faces")
        lines.append("")

        // Generate points array
        lines.append("points = [")
        for (index, point) in uniquePoints.enumerated() {
            let comma = index < uniquePoints.count - 1 ? "," : ""
            lines.append("    [\(formatNumber(point.x)), \(formatNumber(point.y)), \(formatNumber(point.z))]\(comma)  // \(index)")
        }
        lines.append("];")
        lines.append("")

        // Generate faces array
        lines.append("faces = [")
        for (index, face) in faces.enumerated() {
            let comma = index < faces.count - 1 ? "," : ""
            if face.count == 3 {
                lines.append("    [\(face[0]), \(face[1]), \(face[2])]\(comma)")
            } else {
                // For polygons with more than 3 vertices
                let faceStr = face.map { String($0) }.joined(separator: ", ")
                lines.append("    [\(faceStr)]\(comma)")
            }
        }
        lines.append("];")
        lines.append("")

        // Generate polyhedron
        lines.append("polyhedron(points = points, faces = faces, convexity = 10);")

        return lines.joined(separator: "\n")
    }

    /// Find open edges and generate faces to close the mesh
    /// An edge is "open" if it only appears in one face (not shared by two faces)
    private static func generateClosingFaces(points: [Vector3], existingFaces: [[Int]]) -> [[Int]] {
        // Count how many times each edge appears (edge = sorted pair of vertex indices)
        var edgeCount: [String: Int] = [:]
        var edgeFaceNormal: [String: Vector3] = [:]

        for face in existingFaces {
            guard face.count >= 3 else { continue }

            // Calculate face normal for winding order
            let v0 = points[face[0]]
            let v1 = points[face[1]]
            let v2 = points[face[2]]
            let normal = (v1 - v0).cross(v2 - v0).normalized()

            // Process each edge of the face
            for i in 0..<face.count {
                let a = face[i]
                let b = face[(i + 1) % face.count]
                let edgeKey = a < b ? "\(a)-\(b)" : "\(b)-\(a)"
                edgeCount[edgeKey, default: 0] += 1
                edgeFaceNormal[edgeKey] = normal
            }
        }

        // Find open edges (appear only once)
        var openEdges: [(Int, Int)] = []
        for (edgeKey, count) in edgeCount {
            if count == 1 {
                let parts = edgeKey.split(separator: "-")
                if parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) {
                    openEdges.append((a, b))
                }
            }
        }

        guard !openEdges.isEmpty else { return [] }

        // Try to form closed loops from open edges and create faces
        var closingFaces: [[Int]] = []
        var remainingEdges = openEdges

        while !remainingEdges.isEmpty {
            // Start a new loop
            var loop: [Int] = []
            let firstEdge = remainingEdges.removeFirst()
            loop.append(firstEdge.0)
            loop.append(firstEdge.1)

            var currentVertex = firstEdge.1
            let startVertex = firstEdge.0

            // Try to complete the loop
            var foundNext = true
            while foundNext && currentVertex != startVertex {
                foundNext = false
                for i in 0..<remainingEdges.count {
                    let edge = remainingEdges[i]
                    if edge.0 == currentVertex {
                        currentVertex = edge.1
                        if currentVertex != startVertex {
                            loop.append(currentVertex)
                        }
                        remainingEdges.remove(at: i)
                        foundNext = true
                        break
                    } else if edge.1 == currentVertex {
                        currentVertex = edge.0
                        if currentVertex != startVertex {
                            loop.append(currentVertex)
                        }
                        remainingEdges.remove(at: i)
                        foundNext = true
                        break
                    }
                }
            }

            // If we completed a loop (3+ vertices), create a face
            if loop.count >= 3 && currentVertex == startVertex {
                // Determine correct winding order
                // Calculate the centroid and normal of the loop
                var centroid = Vector3(0, 0, 0)
                for idx in loop {
                    centroid = centroid + points[idx]
                }
                centroid = centroid / Double(loop.count)

                // Calculate loop normal
                let loopNormal = calculatePolygonNormal(points: points, indices: loop)

                // Check if we need to reverse the winding
                // Compare with the average normal of adjacent faces
                var avgAdjacentNormal = Vector3(0, 0, 0)
                var adjacentCount = 0
                for i in 0..<loop.count {
                    let a = loop[i]
                    let b = loop[(i + 1) % loop.count]
                    let edgeKey = a < b ? "\(a)-\(b)" : "\(b)-\(a)"
                    if let normal = edgeFaceNormal[edgeKey] {
                        avgAdjacentNormal = avgAdjacentNormal + normal
                        adjacentCount += 1
                    }
                }

                if adjacentCount > 0 {
                    avgAdjacentNormal = avgAdjacentNormal / Double(adjacentCount)
                    // The closing face should have opposite normal to create a closed solid
                    // If normals point same direction, reverse the loop
                    if loopNormal.dot(avgAdjacentNormal) > 0 {
                        closingFaces.append(loop.reversed())
                    } else {
                        closingFaces.append(loop)
                    }
                } else {
                    closingFaces.append(loop)
                }
            }
        }

        return closingFaces
    }

    /// Calculate the normal of a polygon defined by point indices
    private static func calculatePolygonNormal(points: [Vector3], indices: [Int]) -> Vector3 {
        guard indices.count >= 3 else { return Vector3(0, 0, 1) }

        // Use Newell's method for robust normal calculation
        var normal = Vector3(0, 0, 0)
        for i in 0..<indices.count {
            let current = points[indices[i]]
            let next = points[indices[(i + 1) % indices.count]]
            normal = normal + Vector3(
                (current.y - next.y) * (current.z + next.z),
                (current.z - next.z) * (current.x + next.x),
                (current.x - next.x) * (current.y + next.y)
            )
        }
        return normal.normalized()
    }

    /// Generate OpenSCAD code from a set of measurements
    /// - Parameter measurements: Array of measurements to convert
    /// - Returns: OpenSCAD code string
    static func generate(from measurements: [Measurement]) -> String {
        guard !measurements.isEmpty else {
            return "// No measurements to convert"
        }

        var lines: [String] = []
        lines.append("// OpenSCAD code generated from GoSTL measurements")
        lines.append("// Generated: \(formattedDate())")
        lines.append("")

        // Group measurements by type for cleaner output
        let distanceMeasurements = measurements.filter { $0.type == .distance }
        let radiusMeasurements = measurements.filter { $0.type == .radius }
        let angleMeasurements = measurements.filter { $0.type == .angle }

        // Try to generate 3D polyhedron from distance measurements
        if let polyhedronCode = generate3DPolyhedron(from: distanceMeasurements) {
            lines.append(polyhedronCode)
        } else if !distanceMeasurements.isEmpty {
            // Fall back to individual 3D edges
            lines.append("// Distance measurements as 3D edges")
            lines.append("edge_radius = 0.5;  // Adjust edge thickness as needed")
            lines.append("")
            for (index, measurement) in distanceMeasurements.enumerated() {
                lines.append(generate3DEdge(from: measurement, index: index))
            }
            lines.append("")
        }

        // Generate 3D cylinders from radius measurements
        if !radiusMeasurements.isEmpty {
            lines.append("// Cylinders from radius measurements")
            lines.append("cylinder_height = 1;  // Adjust height as needed")
            lines.append("")
            for (index, measurement) in radiusMeasurements.enumerated() {
                lines.append(generate3DCylinder(from: measurement, index: index))
            }
            lines.append("")
        }

        // Add angle comments with potential wedge generation
        if !angleMeasurements.isEmpty {
            lines.append("// Angle measurements")
            for (index, measurement) in angleMeasurements.enumerated() {
                lines.append(generate3DAngle(from: measurement, index: index))
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - 3D Polyhedron Generation

    /// Try to generate a 3D polyhedron from distance measurements
    private static func generate3DPolyhedron(from distanceMeasurements: [Measurement]) -> String? {
        guard distanceMeasurements.count >= 3 else { return nil }

        // Extract all unique 3D points
        var allPoints: [Vector3] = []
        var edges: [(Int, Int)] = []

        for measurement in distanceMeasurements {
            guard measurement.points.count >= 2 else { continue }
            let p1 = measurement.points[0].position
            let p2 = measurement.points[1].position

            // Find or add points
            let idx1 = findOrAddPoint(p1, in: &allPoints)
            let idx2 = findOrAddPoint(p2, in: &allPoints)

            edges.append((idx1, idx2))
        }

        // Need at least 4 points for a 3D polyhedron
        guard allPoints.count >= 4 else { return nil }

        // Check if points are coplanar - if so, generate extruded polygon instead
        if arePointsCoplanar(allPoints) {
            return generateExtrudedPolygon(points: allPoints, edges: edges)
        }

        // Try to generate a proper polyhedron with faces
        return generatePolyhedronWithFaces(points: allPoints, edges: edges)
    }

    /// Find existing point or add new one, return index
    private static func findOrAddPoint(_ point: Vector3, in points: inout [Vector3]) -> Int {
        for (index, existing) in points.enumerated() {
            if point.distance(to: existing) < 0.01 {
                return index
            }
        }
        points.append(point)
        return points.count - 1
    }

    /// Check if all points lie on the same plane
    private static func arePointsCoplanar(_ points: [Vector3]) -> Bool {
        guard points.count >= 4 else { return true }

        // Calculate plane normal from first 3 points
        let v1 = points[1] - points[0]
        let v2 = points[2] - points[0]
        let normal = v1.cross(v2)

        if normal.length < 0.001 {
            return true  // Points are collinear
        }

        let normalizedNormal = normal.normalized()

        // Check if all other points are on this plane
        for i in 3..<points.count {
            let v = points[i] - points[0]
            let distance = abs(v.dot(normalizedNormal))
            if distance > 0.1 {
                return false
            }
        }

        return true
    }

    /// Generate an extruded polygon for coplanar points
    private static func generateExtrudedPolygon(points: [Vector3], edges: [(Int, Int)]) -> String {
        // Find the plane and project points
        let planeInfo = determinePlane(points: points)

        var lines: [String] = []
        lines.append("// Extruded polygon from \(points.count) coplanar points")

        // Sort points to form a proper polygon outline
        let sortedIndices = sortPointsForPolygon(points: points, plane: planeInfo.plane)
        let sortedPoints = sortedIndices.map { points[$0] }

        // Generate 2D points
        let points2D = project2D(points: sortedPoints, plane: planeInfo.plane)

        lines.append("polygon_points = [")
        for (index, point) in points2D.enumerated() {
            let comma = index < points2D.count - 1 ? "," : ""
            lines.append("    [\(formatNumber(point.0)), \(formatNumber(point.1))]\(comma)")
        }
        lines.append("];")
        lines.append("")

        // Calculate extrusion height based on plane
        let extrudeHeight = "extrude_height"
        lines.append("\(extrudeHeight) = 1;  // Adjust extrusion height as needed")
        lines.append("")

        // Apply transformations based on plane orientation
        switch planeInfo.plane {
        case .xy:
            if abs(planeInfo.offset) > 0.01 {
                lines.append("translate([0, 0, \(formatNumber(planeInfo.offset))])")
            }
            lines.append("linear_extrude(height = \(extrudeHeight))")
        case .xz:
            lines.append("translate([0, \(formatNumber(planeInfo.offset)), 0])")
            lines.append("rotate([90, 0, 0])")
            lines.append("linear_extrude(height = \(extrudeHeight))")
        case .yz:
            lines.append("translate([\(formatNumber(planeInfo.offset)), 0, 0])")
            lines.append("rotate([0, 90, 0])")
            lines.append("linear_extrude(height = \(extrudeHeight))")
        case .arbitrary:
            // For arbitrary planes, use multmatrix
            lines.append("// Note: Arbitrary plane - adjust transformation as needed")
            lines.append("linear_extrude(height = \(extrudeHeight))")
        }

        lines.append("    polygon(polygon_points);")

        return lines.joined(separator: "\n")
    }

    /// Sort points to form a proper polygon outline (counterclockwise)
    private static func sortPointsForPolygon(points: [Vector3], plane: Plane) -> [Int] {
        let points2D = project2D(points: points, plane: plane)

        // Calculate centroid
        let cx = points2D.map { $0.0 }.reduce(0, +) / Double(points2D.count)
        let cy = points2D.map { $0.1 }.reduce(0, +) / Double(points2D.count)

        // Sort by angle from centroid
        let indices = points.indices.sorted { i, j in
            let a1 = atan2(points2D[i].1 - cy, points2D[i].0 - cx)
            let a2 = atan2(points2D[j].1 - cy, points2D[j].0 - cx)
            return a1 < a2
        }

        return indices
    }

    /// Generate a polyhedron with automatically detected faces
    private static func generatePolyhedronWithFaces(points: [Vector3], edges: [(Int, Int)]) -> String? {
        // Try to detect if this is a cube/box
        if let cubeCode = detectAndGenerateCube(points: points) {
            return cubeCode
        }

        // For complex 3D shapes, generate a convex hull or wireframe
        var lines: [String] = []
        lines.append("// 3D shape from \(points.count) points")
        lines.append("// Using hull() to create convex solid")
        lines.append("")
        lines.append("point_radius = 0.1;  // Small spheres at vertices")
        lines.append("")
        lines.append("hull() {")

        for (index, point) in points.enumerated() {
            lines.append("    // Point \(index + 1)")
            lines.append("    translate([\(formatNumber(point.x)), \(formatNumber(point.y)), \(formatNumber(point.z))])")
            lines.append("        sphere(r = point_radius, $fn = 16);")
        }

        lines.append("}")
        lines.append("")

        // Also provide the explicit polyhedron definition for reference
        lines.append("// Alternative: Explicit polyhedron (uncomment and adjust faces)")
        lines.append("/*")
        lines.append("polyhedron_points = [")
        for (index, point) in points.enumerated() {
            let comma = index < points.count - 1 ? "," : ""
            lines.append("    [\(formatNumber(point.x)), \(formatNumber(point.y)), \(formatNumber(point.z))]\(comma)  // Point \(index)")
        }
        lines.append("];")
        lines.append("")
        lines.append("// Define faces as lists of point indices (counterclockwise when viewed from outside)")
        lines.append("polyhedron_faces = [")
        lines.append("    // Add face definitions here, e.g.:")
        lines.append("    // [0, 1, 2],  // Triangle face")
        lines.append("    // [0, 2, 3],  // Another face")
        lines.append("];")
        lines.append("")
        lines.append("polyhedron(points = polyhedron_points, faces = polyhedron_faces);")
        lines.append("*/")

        return lines.joined(separator: "\n")
    }

    /// Detect if points form a cube/box and generate appropriate OpenSCAD
    private static func detectAndGenerateCube(points: [Vector3]) -> String? {
        // A cube has exactly 8 vertices
        guard points.count == 8 else { return nil }

        // Find bounding box
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        var minZ = Double.infinity, maxZ = -Double.infinity

        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
            minZ = min(minZ, p.z)
            maxZ = max(maxZ, p.z)
        }

        let sizeX = maxX - minX
        let sizeY = maxY - minY
        let sizeZ = maxZ - minZ

        // Check if all points are at the corners of this bounding box
        let corners = [
            Vector3(minX, minY, minZ),
            Vector3(maxX, minY, minZ),
            Vector3(minX, maxY, minZ),
            Vector3(maxX, maxY, minZ),
            Vector3(minX, minY, maxZ),
            Vector3(maxX, minY, maxZ),
            Vector3(minX, maxY, maxZ),
            Vector3(maxX, maxY, maxZ)
        ]

        // Check if each point matches a corner
        for point in points {
            var foundMatch = false
            for corner in corners {
                if point.distance(to: corner) < 0.1 {
                    foundMatch = true
                    break
                }
            }
            if !foundMatch {
                return nil  // Not a cube
            }
        }

        // This is a cube/box!
        var lines: [String] = []

        // Check if it's a perfect cube
        let tolerance = 0.1
        let isCube = abs(sizeX - sizeY) < tolerance && abs(sizeY - sizeZ) < tolerance

        if isCube {
            lines.append("// Cube detected: side = \(formatNumber(sizeX))")
        } else {
            lines.append("// Box detected: \(formatNumber(sizeX)) x \(formatNumber(sizeY)) x \(formatNumber(sizeZ))")
        }
        lines.append("")

        // Generate OpenSCAD cube
        lines.append("translate([\(formatNumber(minX)), \(formatNumber(minY)), \(formatNumber(minZ))])")

        if isCube {
            lines.append("    cube(\(formatNumber(sizeX)));")
        } else {
            lines.append("    cube([\(formatNumber(sizeX)), \(formatNumber(sizeY)), \(formatNumber(sizeZ))]);")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Individual 3D Elements

    /// Generate a 3D edge/cylinder between two points
    private static func generate3DEdge(from measurement: Measurement, index: Int) -> String {
        guard measurement.points.count >= 2 else {
            return "// Edge \(index + 1): invalid (not enough points)"
        }

        let p1 = measurement.points[0].position
        let p2 = measurement.points[1].position
        let length = measurement.value

        // Calculate direction and rotation
        let direction = p2 - p1
        let dirNorm = direction.normalized()

        // Calculate rotation from Z axis to direction
        let rotationCode = calculateCylinderRotation(direction: dirNorm)

        var lines: [String] = []
        lines.append("// Edge \(index + 1): length = \(formatNumber(length))")
        lines.append("translate([\(formatNumber(p1.x)), \(formatNumber(p1.y)), \(formatNumber(p1.z))])")
        lines.append(rotationCode)
        lines.append("    cylinder(h = \(formatNumber(length)), r = edge_radius, $fn = 16);")

        return lines.joined(separator: "\n")
    }

    /// Calculate rotation to align Z-axis cylinder with given direction
    private static func calculateCylinderRotation(direction: Vector3) -> String {
        // OpenSCAD cylinders are along Z-axis by default
        // We need to rotate to align with the direction vector

        // If direction is already along Z
        if abs(direction.z - 1.0) < 0.001 {
            return ""
        }

        // If direction is along -Z
        if abs(direction.z + 1.0) < 0.001 {
            return "rotate([180, 0, 0])"
        }

        // Calculate spherical angles
        let r = direction.length
        if r < 0.001 { return "" }

        // Angle from positive Z axis (inclination)
        let theta = acos(direction.z / r) * 180.0 / .pi

        // Angle in XY plane from positive X axis (azimuth)
        let phi = atan2(direction.y, direction.x) * 180.0 / .pi

        // Rotate: first around Z by phi, then around Y by theta
        return "rotate([0, \(formatNumber(theta)), \(formatNumber(phi))])"
    }

    /// Generate a 3D cylinder from radius measurement
    private static func generate3DCylinder(from measurement: Measurement, index: Int) -> String {
        guard let circle = measurement.circle else {
            return "// Cylinder \(index + 1): invalid (no circle data)"
        }

        let center = circle.center
        let radius = circle.radius
        let normal = circle.normal

        var lines: [String] = []
        lines.append("// Cylinder \(index + 1): radius = \(formatNumber(radius))")
        lines.append("translate([\(formatNumber(center.x)), \(formatNumber(center.y)), \(formatNumber(center.z))])")

        // Calculate rotation to align cylinder axis with circle normal
        let rotationCode = calculateCylinderRotation(direction: normal)
        if !rotationCode.isEmpty {
            lines.append(rotationCode)
        }

        lines.append("    cylinder(h = cylinder_height, r = \(formatNumber(radius)), center = true, $fn = 64);")

        return lines.joined(separator: "\n")
    }

    /// Generate 3D representation of an angle measurement
    private static func generate3DAngle(from measurement: Measurement, index: Int) -> String {
        guard measurement.points.count >= 3 else {
            return "// Angle \(index + 1): invalid (not enough points)"
        }

        let p1 = measurement.points[0].position
        let vertex = measurement.points[1].position
        let p2 = measurement.points[2].position
        let angle = measurement.value

        var lines: [String] = []
        lines.append("// Angle \(index + 1): \(formatNumber(angle)) degrees")
        lines.append("// Vertex at [\(formatNumber(vertex.x)), \(formatNumber(vertex.y)), \(formatNumber(vertex.z))]")

        // Generate two edges from vertex to show the angle
        let edge1 = p1 - vertex
        let edge2 = p2 - vertex
        let len1 = edge1.length
        let len2 = edge2.length

        lines.append("angle_edge_radius = 0.3;")
        lines.append("")
        lines.append("// First edge of angle")
        lines.append("translate([\(formatNumber(vertex.x)), \(formatNumber(vertex.y)), \(formatNumber(vertex.z))])")
        lines.append(calculateCylinderRotation(direction: edge1.normalized()))
        lines.append("    cylinder(h = \(formatNumber(len1)), r = angle_edge_radius, $fn = 16);")
        lines.append("")
        lines.append("// Second edge of angle")
        lines.append("translate([\(formatNumber(vertex.x)), \(formatNumber(vertex.y)), \(formatNumber(vertex.z))])")
        lines.append(calculateCylinderRotation(direction: edge2.normalized()))
        lines.append("    cylinder(h = \(formatNumber(len2)), r = angle_edge_radius, $fn = 16);")
        lines.append("")
        lines.append("// Vertex sphere")
        lines.append("translate([\(formatNumber(vertex.x)), \(formatNumber(vertex.y)), \(formatNumber(vertex.z))])")
        lines.append("    sphere(r = angle_edge_radius * 1.5, $fn = 16);")

        return lines.joined(separator: "\n")
    }

    // MARK: - Helper Methods

    private static func formatNumber(_ value: Double) -> String {
        if abs(value) < 0.0001 {
            return "0"
        }
        return String(format: "%.4f", value).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }

    private static func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    private enum Plane {
        case xy  // Z is constant
        case xz  // Y is constant
        case yz  // X is constant
        case arbitrary
    }

    private static func determinePlane(points: [Vector3]) -> (plane: Plane, offset: Double) {
        guard let first = points.first else {
            return (.xy, 0)
        }

        // Check if all points have same Z (XY plane)
        let allSameZ = points.allSatisfy { abs($0.z - first.z) < 0.1 }
        if allSameZ {
            return (.xy, first.z)
        }

        // Check if all points have same Y (XZ plane)
        let allSameY = points.allSatisfy { abs($0.y - first.y) < 0.1 }
        if allSameY {
            return (.xz, first.y)
        }

        // Check if all points have same X (YZ plane)
        let allSameX = points.allSatisfy { abs($0.x - first.x) < 0.1 }
        if allSameX {
            return (.yz, first.x)
        }

        // Default to arbitrary plane
        return (.arbitrary, 0)
    }

    private static func project2D(points: [Vector3], plane: Plane) -> [(Double, Double)] {
        switch plane {
        case .xy:
            return points.map { ($0.x, $0.y) }
        case .xz:
            return points.map { ($0.x, $0.z) }
        case .yz:
            return points.map { ($0.y, $0.z) }
        case .arbitrary:
            // For arbitrary planes, project onto XY
            return points.map { ($0.x, $0.y) }
        }
    }

    /// Copy generated code to clipboard
    static func copyToClipboard(_ code: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
    }

    // MARK: - Polygon Generation from Measurements

    /// Generate OpenSCAD polygon code from distance measurements
    /// - Parameter measurements: Array of distance measurements to convert to polygon points
    /// - Returns: OpenSCAD code string with polygon definition
    static func generatePolygon(from measurements: [Measurement]) -> String {
        // Filter to only distance measurements
        let distanceMeasurements = measurements.filter { $0.type == .distance }

        guard !distanceMeasurements.isEmpty else {
            return "// No distance measurements to convert to polygon"
        }

        var lines: [String] = []
        lines.append("// OpenSCAD polygon generated from GoSTL measurements")
        lines.append("// Generated: \(formattedDate())")
        lines.append("// Measurements: \(distanceMeasurements.count)")
        lines.append("")

        // Extract all unique points from measurements
        var allPoints: [Vector3] = []
        var pointOrder: [Int] = []  // Track order of points for polygon

        for measurement in distanceMeasurements {
            guard measurement.points.count >= 2 else { continue }
            let p1 = measurement.points[0].position
            let p2 = measurement.points[1].position

            let idx1 = findOrAddPoint(p1, in: &allPoints)
            let idx2 = findOrAddPoint(p2, in: &allPoints)

            // Add to point order if not already tracked
            if !pointOrder.contains(idx1) {
                pointOrder.append(idx1)
            }
            if !pointOrder.contains(idx2) {
                pointOrder.append(idx2)
            }
        }

        guard allPoints.count >= 2 else {
            return "// Not enough points for a polygon"
        }

        // Determine the best projection plane
        let planeInfo = determinePlane(points: allPoints)

        lines.append("// Points projected onto \(planeDescription(planeInfo.plane)) plane")
        lines.append("")

        // Project points to 2D
        let points2D = project2D(points: allPoints, plane: planeInfo.plane)

        // Sort points to form a proper polygon outline
        let sortedIndices = sortPointsForPolygon(points: allPoints, plane: planeInfo.plane)

        lines.append("// \(allPoints.count) unique points")
        lines.append("polygon_points = [")
        for (index, pointIdx) in sortedIndices.enumerated() {
            let point2D = points2D[pointIdx]
            let point3D = allPoints[pointIdx]
            let comma = index < sortedIndices.count - 1 ? "," : ""
            lines.append("    [\(formatNumber(point2D.0)), \(formatNumber(point2D.1))]\(comma)  // Point \(index): 3D=(\(formatNumber(point3D.x)), \(formatNumber(point3D.y)), \(formatNumber(point3D.z)))")
        }
        lines.append("];")
        lines.append("")

        // Generate polygon
        lines.append("polygon(points = polygon_points);")
        lines.append("")

        // Also provide extruded version
        lines.append("// Extruded version (uncomment to use):")
        lines.append("// extrude_height = 1;")

        // Add transformation based on plane
        switch planeInfo.plane {
        case .xy:
            if abs(planeInfo.offset) > 0.01 {
                lines.append("// translate([0, 0, \(formatNumber(planeInfo.offset))])")
            }
            lines.append("// linear_extrude(height = extrude_height)")
        case .xz:
            lines.append("// translate([0, \(formatNumber(planeInfo.offset)), 0])")
            lines.append("// rotate([90, 0, 0])")
            lines.append("// linear_extrude(height = extrude_height)")
        case .yz:
            lines.append("// translate([\(formatNumber(planeInfo.offset)), 0, 0])")
            lines.append("// rotate([0, 90, 0])")
            lines.append("// linear_extrude(height = extrude_height)")
        case .arbitrary:
            lines.append("// linear_extrude(height = extrude_height)")
        }
        lines.append("//     polygon(polygon_points);")

        return lines.joined(separator: "\n")
    }

    /// Get a description of the plane
    private static func planeDescription(_ plane: Plane) -> String {
        switch plane {
        case .xy: return "XY"
        case .xz: return "XZ"
        case .yz: return "YZ"
        case .arbitrary: return "XY (arbitrary)"
        }
    }
}
