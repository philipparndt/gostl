import SwiftUI

/// Overlay that shows grid coordinate labels and dimension lines
struct GridOverlay: View {
    let gridData: GridData?
    let gridMode: GridMode
    let camera: Camera
    let viewSize: CGSize
    let boundingBox: BoundingBox?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Only show labels and dimensions if grid is visible and we have grid data
                if gridMode != .off, let gridData = gridData, let bbox = boundingBox {
                    // Grid coordinate labels (white)
                    gridLabels(gridData: gridData, bbox: bbox)

                    // Dimension lines (yellow)
                    dimensionLines(gridData: gridData, bbox: bbox)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Grid Labels (Z-up coordinate system)

    @ViewBuilder
    private func gridLabels(gridData: GridData, bbox: BoundingBox) -> some View {
        let bounds = gridData.bounds
        let spacing = gridData.gridSpacing
        let labelColor = Color(red: 200/255, green: 200/255, blue: 200/255)

        // Determine label spacing based on mode
        let labelSpacing: Float = gridMode == .oneMM ? 10.0 : spacing

        // X labels along front edge (at minY)
        ForEach(generateLabelPositions(min: bounds.minX, max: bounds.maxX, spacing: labelSpacing), id: \.self) { x in
            if let screenPos = camera.project(
                worldPosition: Vector3(Double(x), Double(bounds.minY - 2), Double(bounds.bottomZ)),
                viewSize: viewSize
            ) {
                GridLabel(text: formatCoordinate(x), position: screenPos, color: labelColor)
            }
        }

        // Y labels along left edge (skip "0")
        ForEach(generateLabelPositions(min: bounds.minY, max: bounds.maxY, spacing: labelSpacing), id: \.self) { y in
            // Skip "0" on Y axis to avoid duplicate with X axis
            if abs(y) > 0.001 {
                if let screenPos = camera.project(
                    worldPosition: Vector3(Double(bounds.minX - 2), Double(y), Double(bounds.bottomZ)),
                    viewSize: viewSize
                ) {
                    GridLabel(text: formatCoordinate(y), position: screenPos, color: labelColor)
                }
            }
        }

        // Z labels (vertical, only in allSides and oneMM modes)
        if gridMode == .allSides || gridMode == .oneMM {
            ForEach(generateLabelPositions(min: bounds.minZ, max: bounds.maxZ, spacing: labelSpacing), id: \.self) { z in
                // Skip "0" on Z axis to avoid duplicate
                if abs(z) > 0.001 {
                    if let screenPos = camera.project(
                        worldPosition: Vector3(Double(bounds.minX - 2), Double(bounds.maxY + 2), Double(z)),
                        viewSize: viewSize
                    ) {
                        GridLabel(text: formatCoordinate(z), position: screenPos, color: labelColor)
                    }
                }
            }
        }
    }

    // MARK: - Dimension Lines (Z-up coordinate system)

    @ViewBuilder
    private func dimensionLines(gridData: GridData, bbox: BoundingBox) -> some View {
        let dimColor = Color(red: 255/255, green: 200/255, blue: 100/255)
        let offset: Float = 5.0

        let bboxMinX = Float(bbox.min.x)
        let bboxMaxX = Float(bbox.max.x)
        let bboxMinY = Float(bbox.min.y)
        let bboxMaxY = Float(bbox.max.y)
        let bboxMinZ = Float(bbox.min.z)
        let bboxMaxZ = Float(bbox.max.z)
        let z = gridData.bounds.bottomZ

        // X dimension (width) - front edge
        if let start = camera.project(
            worldPosition: Vector3(Double(bboxMinX), Double(bboxMinY - offset), Double(z - offset)),
            viewSize: viewSize
        ), let end = camera.project(
            worldPosition: Vector3(Double(bboxMaxX), Double(bboxMinY - offset), Double(z - offset)),
            viewSize: viewSize
        ), let mid = camera.project(
            worldPosition: Vector3(Double((bboxMinX + bboxMaxX) / 2), Double(bboxMinY - offset - 3), Double(z - offset)),
            viewSize: viewSize
        ) {
            DimensionLine(start: start, end: end, color: dimColor)
            DimensionLabel(
                text: String(format: "X: %.1f mm", bboxMaxX - bboxMinX),
                position: mid,
                color: dimColor
            )
        }

        // Y dimension (depth) - left edge
        if let start = camera.project(
            worldPosition: Vector3(Double(bboxMinX - offset), Double(bboxMinY), Double(z - offset)),
            viewSize: viewSize
        ), let end = camera.project(
            worldPosition: Vector3(Double(bboxMinX - offset), Double(bboxMaxY), Double(z - offset)),
            viewSize: viewSize
        ), let mid = camera.project(
            worldPosition: Vector3(Double(bboxMinX - offset - 3), Double((bboxMinY + bboxMaxY) / 2), Double(z - offset)),
            viewSize: viewSize
        ) {
            DimensionLine(start: start, end: end, color: dimColor)
            DimensionLabel(
                text: String(format: "Y: %.1f mm", bboxMaxY - bboxMinY),
                position: mid,
                color: dimColor
            )
        }

        // Z dimension (height) - vertical on back-right corner
        if let start = camera.project(
            worldPosition: Vector3(Double(bboxMaxX + offset), Double(bboxMaxY + offset), Double(bboxMinZ)),
            viewSize: viewSize
        ), let end = camera.project(
            worldPosition: Vector3(Double(bboxMaxX + offset), Double(bboxMaxY + offset), Double(bboxMaxZ)),
            viewSize: viewSize
        ), let mid = camera.project(
            worldPosition: Vector3(Double(bboxMaxX + offset + 3), Double(bboxMaxY + offset), Double((bboxMinZ + bboxMaxZ) / 2)),
            viewSize: viewSize
        ) {
            DimensionLine(start: start, end: end, color: dimColor)
            DimensionLabel(
                text: String(format: "Z: %.1f mm", bboxMaxZ - bboxMinZ),
                position: mid,
                color: dimColor
            )
        }
    }

    // MARK: - Helper Functions

    private func generateLabelPositions(min: Float, max: Float, spacing: Float) -> [Float] {
        var positions: [Float] = []
        var current = ceil(min / spacing) * spacing
        while current <= max {
            positions.append(current)
            current += spacing
        }
        return positions
    }

    private func formatCoordinate(_ value: Float) -> String {
        return String(format: "%.0f", value)
    }
}

// MARK: - Supporting Views

/// A single grid coordinate label
private struct GridLabel: View {
    let text: String
    let position: CGPoint
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.5))
            )
            .position(position)
    }
}

/// A dimension line between two points
private struct DimensionLine: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color

    var body: some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(color, lineWidth: 2)
    }
}

/// A dimension label with yellow background
private struct DimensionLabel: View {
    let text: String
    let position: CGPoint
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            )
            .position(position)
    }
}
