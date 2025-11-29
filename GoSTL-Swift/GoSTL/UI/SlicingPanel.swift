import SwiftUI

/// Panel for controlling model slicing on X, Y, Z axes
struct SlicingPanel: View {
    let slicingState: SlicingState

    // Axis colors (matching 3D convention)
    private let axisColors: [Color] = [
        Color(red: 1.0, green: 0.31, blue: 0.31),   // X - Red
        Color(red: 0.31, green: 1.0, blue: 0.31),   // Y - Green
        Color(red: 0.31, green: 0.47, blue: 1.0)    // Z - Blue
    ]

    private let axisNames = ["X", "Y", "Z"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title bar with toggle buttons
            HStack(spacing: 8) {
                Text("MODEL SLICING")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.39, green: 0.78, blue: 1.0))

                Spacer()

                // Fill toggle
                ToggleButton(
                    label: "Fill",
                    isOn: slicingState.fillCrossSections,
                    action: { slicingState.fillCrossSections.toggle() }
                )

                // Planes toggle
                ToggleButton(
                    label: "Planes",
                    isOn: slicingState.showPlanes,
                    action: { slicingState.showPlanes.toggle() }
                )
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // Sliders for each axis
            ForEach(0..<3, id: \.self) { axis in
                VStack(alignment: .leading, spacing: 8) {
                    // Axis label
                    Text("\(axisNames[axis]) Axis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(axisColors[axis])

                    // Min slider
                    SliderRow(
                        label: "Min",
                        value: Binding(
                            get: { slicingState.bounds[axis][0] },
                            set: { newValue in
                                // Ensure min <= max
                                slicingState.bounds[axis][0] = min(newValue, slicingState.bounds[axis][1])
                            }
                        ),
                        range: slicingState.modelBounds[axis][0]...slicingState.modelBounds[axis][1],
                        color: axisColors[axis],
                        axis: axis,
                        isMin: true,
                        slicingState: slicingState
                    )

                    // Max slider
                    SliderRow(
                        label: "Max",
                        value: Binding(
                            get: { slicingState.bounds[axis][1] },
                            set: { newValue in
                                // Ensure max >= min
                                slicingState.bounds[axis][1] = max(newValue, slicingState.bounds[axis][0])
                            }
                        ),
                        range: slicingState.modelBounds[axis][0]...slicingState.modelBounds[axis][1],
                        color: axisColors[axis],
                        axis: axis,
                        isMin: false,
                        slicingState: slicingState
                    )
                }
                .padding(.vertical, 4)

                if axis < 2 {
                    Divider()
                        .background(Color.white.opacity(0.2))
                }
            }

            // Help text
            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.top, 4)

            HStack(spacing: 4) {
                KeyHint_Slicing(key: "⇧S")
                Text("Hide UI")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
                Text("|")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                KeyHint_Slicing(key: "R")
                Text("Reset")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
                .shadow(radius: 5)
        )
        .frame(width: 300)
    }
}

// MARK: - Helper Views

private struct ToggleButton: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isOn ? .green : .red.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isOn ? Color.green : Color.red.opacity(0.8), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color
    let axis: Int
    let isMin: Bool
    let slicingState: SlicingState

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 30, alignment: .leading)

            Slider(
                value: $value,
                in: range,
                onEditingChanged: { editing in
                    // Show only this plane while dragging
                    if editing {
                        slicingState.activePlane = (axis: axis, isMin: isMin)
                    } else {
                        slicingState.activePlane = nil
                    }
                }
            )
            .tint(color)

            Text(String(format: "%.1f", value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 45, alignment: .trailing)
        }
    }
}

private struct KeyHint_Slicing: View {
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
    let slicingState = SlicingState()
    slicingState.modelBounds = [
        [-50, 50],
        [-50, 50],
        [-50, 50]
    ]
    slicingState.bounds = [
        [-25, 25],
        [-30, 40],
        [-50, 50]
    ]

    return ZStack {
        Color.gray
        SlicingPanel(slicingState: slicingState)
    }
}
