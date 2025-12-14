import SwiftUI

/// Panel for controlling object leveling - align two points along an axis
struct LevelingPanel: View {
    let levelingState: LevelingState
    let onApply: (Int) -> Void  // Called with selected axis (0=X, 1=Y, 2=Z)
    let onCancel: () -> Void
    let onUndo: () -> Void

    private let axisNames = ["X", "Y", "Z"]
    private let axisColors = AxisColors.allUI

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            HStack {
                Text("LEVEL OBJECT")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.39, green: 0.78, blue: 1.0))

                Spacer()

                // Cancel button
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            Divider()
                .background(Color.white.opacity(0.3))

            if levelingState.isReadyForAxisSelection {
                // Axis selection mode
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select axis to level:")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))

                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { axis in
                            AxisButton(
                                label: axisNames[axis],
                                color: axisColors[axis],
                                action: { onApply(axis) }
                            )
                        }
                    }

                    Text("Points will have same \(axisNames[0])/\(axisNames[1])/\(axisNames[2]) coordinate")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                        .italic()
                }
            } else {
                // Point picking mode
                VStack(alignment: .leading, spacing: 6) {
                    Text(levelingState.statusText)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))

                    // Progress indicator
                    HStack(spacing: 8) {
                        PointIndicator(filled: levelingState.point1 != nil, label: "1")
                        PointIndicator(filled: levelingState.point2 != nil, label: "2")
                    }

                    if let p1 = levelingState.point1 {
                        Text("P1: (\(String(format: "%.1f", p1.x)), \(String(format: "%.1f", p1.y)), \(String(format: "%.1f", p1.z)))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    if let p2 = levelingState.point2 {
                        Text("P2: (\(String(format: "%.1f", p2.x)), \(String(format: "%.1f", p2.y)), \(String(format: "%.1f", p2.z)))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // Help text and undo button
            HStack(spacing: 4) {
                LevelingKeyHint(key: "Esc")
                Text("Cancel")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))

                if levelingState.canUndo {
                    Text("|")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))

                    Button(action: onUndo) {
                        HStack(spacing: 2) {
                            LevelingKeyHint(key: "Undo")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
        )
        .frame(width: 220)
    }
}

// MARK: - Helper Views

private struct AxisButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 50, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color)
                        .shadow(color: color.opacity(0.5), radius: 4, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct PointIndicator: View {
    let filled: Bool
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            SwiftUI.Circle()
                .fill(filled ? Color.green : Color.white.opacity(0.3))
                .frame(width: 12, height: 12)
                .overlay(
                    SwiftUI.Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )

            Text("Point \(label)")
                .font(.system(size: 10))
                .foregroundColor(filled ? .green : .white.opacity(0.5))
        }
    }
}

private struct LevelingKeyHint: View {
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
    let levelingState = LevelingState()
    levelingState.isActive = true
    levelingState.point1 = Vector3(10, 20, 30)

    return ZStack {
        Color.gray
        LevelingPanel(
            levelingState: levelingState,
            onApply: { axis in print("Apply axis \(axis)") },
            onCancel: { print("Cancel") },
            onUndo: { print("Undo") }
        )
    }
}
