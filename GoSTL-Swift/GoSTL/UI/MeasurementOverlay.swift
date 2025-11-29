import SwiftUI

/// Overlay that displays measurement information
struct MeasurementOverlay: View {
    let measurementSystem: MeasurementSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Active measurement mode
            if let mode = measurementSystem.mode {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Measuring: \(modeLabel(mode))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Text("Points: \(measurementSystem.pointsNeededText)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))

                    Text("Click on model to pick points")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                        .italic()

                    if mode == .distance {
                        HStack(spacing: 4) {
                            KeyHint_MeasurementLegacy(key: "x")
                            Text("to end / ")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.6))
                            KeyHint_MeasurementLegacy(key: "ESC")
                            Text("to cancel")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.green, lineWidth: 1)
                        )
                )
            }


            // Help text (show when not actively measuring)
            if measurementSystem.mode == nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Measurements")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)

                    Divider()
                        .background(Color.white.opacity(0.3))
                        .padding(.vertical, 2)

                    HStack(spacing: 4) {
                        KeyHint_MeasurementLegacy(key: "d")
                        Text("Distance")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    HStack(spacing: 4) {
                        KeyHint_MeasurementLegacy(key: "a")
                        Text("Angle")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    HStack(spacing: 4) {
                        KeyHint_MeasurementLegacy(key: "c")
                        Text("Radius")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.7))
                        .shadow(radius: 5)
                )
            }
        }
        .fixedSize()
        .padding(12)
    }

    private func modeLabel(_ mode: MeasurementType) -> String {
        switch mode {
        case .distance:
            return "Distance"
        case .angle:
            return "Angle"
        case .radius:
            return "Radius"
        }
    }
}

/// A small keyboard key hint badge (legacy - kept for preview)
private struct KeyHint_MeasurementLegacy: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
            )
    }
}

#Preview {
    let system = MeasurementSystem()
    system.startMeasurement(type: .distance)
    _ = system.addPoint(MeasurementPoint(
        position: Vector3(0, 0, 0),
        normal: Vector3(0, 1, 0)
    ))

    return ZStack {
        Color.gray
        MeasurementOverlay(measurementSystem: system)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
