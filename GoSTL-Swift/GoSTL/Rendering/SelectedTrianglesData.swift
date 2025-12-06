import Metal
import simd

/// GPU-ready data for rendering selected and hovered triangles
final class SelectedTrianglesData {
    let device: MTLDevice

    // Buffers for selected triangles (rendered in cyan/blue)
    var selectedVertexBuffer: MTLBuffer?
    var selectedVertexCount: Int = 0

    // Buffer for hovered triangle (rendered in green)
    var hoveredVertexBuffer: MTLBuffer?
    var hoveredVertexCount: Int = 0

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

            // Hover color: green
            let hoverColor = SIMD4<Float>(0.0, 1.0, 0.3, 1.0)

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
        }
    }
}
