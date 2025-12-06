import Metal
import simd

/// GPU-ready data for rendering selected and hovered triangles
final class SelectedTrianglesData {
    let device: MTLDevice

    // Buffers for selected triangles (rendered in cyan/blue)
    var selectedVertexBuffer: MTLBuffer?
    var selectedVertexCount: Int = 0

    // Buffer for hovered triangle (rendered in green, or blended if selected)
    var hoveredVertexBuffer: MTLBuffer?
    var hoveredVertexCount: Int = 0
    var hoveredTriangleColor: SIMD3<Float> = SIMD3<Float>(0.0, 1.0, 0.3)  // Default green

    init(device: MTLDevice) {
        self.device = device
    }

    /// Update the buffers with current selection state
    func update(model: STLModel?, selectedIndices: Set<Int>, hoveredIndex: Int?) {
        guard let model = model else {
            selectedVertexBuffer = nil
            selectedVertexCount = 0
            hoveredVertexBuffer = nil
            hoveredVertexCount = 0
            return
        }

        // Update selected triangles buffer
        if !selectedIndices.isEmpty {
            var vertices: [VertexIn] = []
            vertices.reserveCapacity(selectedIndices.count * 3)

            // Selection color: cyan
            let selectionColor = SIMD4<Float>(0.0, 0.8, 1.0, 1.0)

            for index in selectedIndices {
                guard index < model.triangles.count else { continue }
                let triangle = model.triangles[index]
                let normal = triangle.normal.float3

                vertices.append(VertexIn(position: triangle.v1.float3, normal: normal, color: selectionColor))
                vertices.append(VertexIn(position: triangle.v2.float3, normal: normal, color: selectionColor))
                vertices.append(VertexIn(position: triangle.v3.float3, normal: normal, color: selectionColor))
            }

            if !vertices.isEmpty {
                let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
                selectedVertexBuffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: [])
                selectedVertexCount = vertices.count
            } else {
                selectedVertexBuffer = nil
                selectedVertexCount = 0
            }
        } else {
            selectedVertexBuffer = nil
            selectedVertexCount = 0
        }

        // Update hovered triangle buffer
        if let hoveredIndex = hoveredIndex, hoveredIndex < model.triangles.count {
            let triangle = model.triangles[hoveredIndex]
            let normal = triangle.normal.float3

            // Use different hover color depending on whether triangle is already selected
            let hoverColor: SIMD4<Float>
            if selectedIndices.contains(hoveredIndex) {
                // Blend of selection color (cyan) and hover color (green)
                // Selection: (0.0, 0.8, 1.0), Hover: (0.0, 1.0, 0.3)
                // Midpoint: (0.0, 0.9, 0.65)
                hoverColor = SIMD4<Float>(0.0, 0.9, 0.65, 1.0)
                hoveredTriangleColor = SIMD3<Float>(0.0, 0.9, 0.65)
            } else {
                // Normal hover color: green
                hoverColor = SIMD4<Float>(0.0, 1.0, 0.3, 1.0)
                hoveredTriangleColor = SIMD3<Float>(0.0, 1.0, 0.3)
            }

            var vertices: [VertexIn] = []
            vertices.append(VertexIn(position: triangle.v1.float3, normal: normal, color: hoverColor))
            vertices.append(VertexIn(position: triangle.v2.float3, normal: normal, color: hoverColor))
            vertices.append(VertexIn(position: triangle.v3.float3, normal: normal, color: hoverColor))

            let bufferSize = vertices.count * MemoryLayout<VertexIn>.stride
            hoveredVertexBuffer = device.makeBuffer(bytes: vertices, length: bufferSize, options: [])
            hoveredVertexCount = vertices.count
        } else {
            hoveredVertexBuffer = nil
            hoveredVertexCount = 0
            hoveredTriangleColor = SIMD3<Float>(0.0, 1.0, 0.3)  // Reset to default
        }
    }
}
