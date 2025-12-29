import SwiftUI

/// Overlay that shows measurement labels at their 3D positions
struct MeasurementLabelsOverlay: View {
    let measurementSystem: MeasurementSystem
    let camera: Camera
    let viewSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Show labels for completed measurements
                ForEach(Array(measurementSystem.measurements.enumerated()), id: \.offset) { index, measurement in
                    if let screenPos = camera.project(worldPosition: measurement.labelPosition, viewSize: viewSize) {
                        let isSelected = measurementSystem.selectedMeasurements.contains(index)
                        let isStale = measurement.hasStalePoints
                        let baseColor: Color = {
                            if isStale {
                                return Color(red: 0.5, green: 0.5, blue: 0.5)  // Gray for stale
                            } else if measurement.type == .radius {
                                return Color(red: 1.0, green: 0.59, blue: 1.0)
                            } else {
                                return .yellow
                            }
                        }()
                        let labelColor: Color = isSelected ? Color(red: 0.3, green: 0.5, blue: 1.0) : baseColor

                        MeasurementLabel(
                            text: measurement.formattedValue,
                            position: screenPos,
                            color: labelColor,
                            isSelected: isSelected,
                            onTap: {
                                toggleSelection(index: index)
                            }
                        )
                    }
                }

                // Show preview label (green) when measuring
                if let previewDistance = measurementSystem.previewDistance,
                   let hoverPoint = measurementSystem.hoverPoint,
                   !measurementSystem.currentPoints.isEmpty {
                    let lastPoint = measurementSystem.currentPoints.last!.position
                    let midpoint = Vector3(
                        (lastPoint.x + hoverPoint.position.x) / 2,
                        (lastPoint.y + hoverPoint.position.y) / 2,
                        (lastPoint.z + hoverPoint.position.z) / 2
                    )

                    if let screenPos = camera.project(worldPosition: midpoint, viewSize: viewSize) {
                        MeasurementLabel(
                            text: formatDistance(previewDistance),
                            position: screenPos,
                            color: .green
                        )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .allowsHitTesting(false)
        }
    }

    private func toggleSelection(index: Int) {
        if measurementSystem.selectedMeasurements.contains(index) {
            measurementSystem.selectedMeasurements.remove(index)
        } else {
            measurementSystem.selectedMeasurements.insert(index)
        }
    }

    private func formatDistance(_ value: Double) -> String {
        if value < 1.0 {
            return String(format: "%.2f", value)
        } else if value < 100.0 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.0f", value)
        }
    }
}

/// A single measurement label at a specific screen position
private struct MeasurementLabel: View {
    let text: String
    let position: CGPoint
    let color: Color
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            )
            .overlay(
                // Add border for selected labels
                isSelected ?
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white, lineWidth: 2)
                    : nil
            )
            .scaleEffect(isSelected ? 1.1 : 1.0)  // Slightly larger when selected
            .position(position)
            .onTapGesture {
                onTap?()
            }
    }
}
