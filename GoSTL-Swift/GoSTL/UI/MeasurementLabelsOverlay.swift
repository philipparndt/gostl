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
                        MeasurementLabel(
                            text: measurement.formattedValue,
                            position: screenPos
                        )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// A single measurement label at a specific screen position
private struct MeasurementLabel: View {
    let text: String
    let position: CGPoint

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.yellow.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            )
            .position(position)
    }
}
