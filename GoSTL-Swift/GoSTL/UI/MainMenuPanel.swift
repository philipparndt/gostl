import SwiftUI

/// Main menu panel with Info, View, and Tools sections
struct MainMenuPanel: View {
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Info Section
            if let modelInfo = appState.modelInfo {
                MenuSection(title: "Info", icon: "info.circle") {
                    InfoSectionContent(modelInfo: modelInfo)
                }
            }

            // View Section
            MenuSection(title: "View", icon: "eye") {
                ViewSectionContent(appState: appState)
            }

            // Tools Section
            MenuSection(title: "Tools", icon: "ruler") {
                ToolsSectionContent(measurementSystem: appState.measurementSystem)
            }

            // Toggle hint
            HStack(spacing: 4) {
                KeyHint(key: "i")
                Text("to toggle panel")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.top, 4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.7))
                .shadow(radius: 5)
        )
        .frame(minWidth: 240)
        .fixedSize()
        .padding(12)
    }
}

// MARK: - Menu Section

struct MenuSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Section Header
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)

            if isExpanded {
                Divider()
                    .background(Color.white.opacity(0.3))

                content()
            }
        }
    }
}

// MARK: - Info Section Content

struct InfoSectionContent: View {
    let modelInfo: ModelInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // File name
            Text(modelInfo.fileName)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)

            // Triangle count
            InfoRow(label: "Triangles:", value: ModelInfo.formatCount(modelInfo.triangleCount))

            // Dimensions
            InfoRow(label: "W:", value: ModelInfo.formatDimension(modelInfo.width))
            InfoRow(label: "H:", value: ModelInfo.formatDimension(modelInfo.height))
            InfoRow(label: "D:", value: ModelInfo.formatDimension(modelInfo.depth))

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 2)

            // Volume and surface area
            InfoRow(label: "Volume:", value: ModelInfo.formatVolume(modelInfo.volume))
            InfoRow(label: "Area:", value: ModelInfo.formatArea(modelInfo.surfaceArea))

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 2)

            // Material and weight
            HStack(spacing: 4) {
                Text("Material:")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
                Text(modelInfo.material.rawValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                KeyHint(key: "m")
            }
            InfoRow(label: "Weight:", value: Material.formatWeight(modelInfo.weight))

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 2)

            // Center position
            VStack(alignment: .leading, spacing: 2) {
                Text("Center:")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
                Text(String(format: "%.1f, %.1f, %.1f",
                           modelInfo.center.x, modelInfo.center.y, modelInfo.center.z))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - View Section Content

struct ViewSectionContent: View {
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Wireframe toggle
            HStack(spacing: 4) {
                Button(action: { appState.showWireframe.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: appState.showWireframe ? "checkmark.square.fill" : "square")
                            .font(.system(size: 10))
                            .foregroundColor(appState.showWireframe ? .blue : .white.opacity(0.5))
                        Text("Wireframe")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                KeyHint(key: "w")
            }

            // Grid toggle
            HStack(spacing: 4) {
                Button(action: { appState.showGrid.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: appState.showGrid ? "checkmark.square.fill" : "square")
                            .font(.system(size: 10))
                            .foregroundColor(appState.showGrid ? .blue : .white.opacity(0.5))
                        Text("Grid")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                KeyHint(key: "g")
            }

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 2)

            // Camera presets
            Text("Camera:")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.8))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                CameraPresetButton(label: "Front", key: "1", preset: .front, camera: appState.camera)
                CameraPresetButton(label: "Back", key: "2", preset: .back, camera: appState.camera)
                CameraPresetButton(label: "Left", key: "3", preset: .left, camera: appState.camera)
                CameraPresetButton(label: "Right", key: "4", preset: .right, camera: appState.camera)
                CameraPresetButton(label: "Top", key: "5", preset: .top, camera: appState.camera)
                CameraPresetButton(label: "Bottom", key: "6", preset: .bottom, camera: appState.camera)
            }

            Button(action: { appState.camera.reset() }) {
                HStack {
                    Spacer()
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9))
                    Text("Reset View")
                        .font(.system(size: 10))
                    Spacer()
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Tools Section Content

struct ToolsSectionContent: View {
    let measurementSystem: MeasurementSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Measurement mode buttons
            if let mode = measurementSystem.mode {
                // Active measurement mode
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Measuring: \(modeLabel(mode))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Text("Points: \(measurementSystem.pointsNeededText)")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.8))

                    Text("Click on model vertices")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                        .italic()

                    // Show preview distance for distance mode
                    if mode == .distance, let previewDist = measurementSystem.previewDistance {
                        Divider()
                            .background(Color.white.opacity(0.2))
                            .padding(.vertical, 2)

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 8))
                                .foregroundColor(.green.opacity(0.8))
                            Text(formatDistance(previewDist))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }

                    if mode == .distance {
                        HStack(spacing: 4) {
                            KeyHint(key: "⌫")
                            Text("Undo")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.7))
                            Text("/")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                            KeyHint(key: "x")
                            Text("End")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.7))
                            Text("/")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                            KeyHint(key: "ESC")
                            Text("Cancel")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.top, 2)
                    } else {
                        HStack(spacing: 4) {
                            KeyHint(key: "ESC")
                            Text("Cancel")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.green.opacity(0.4), lineWidth: 1)
                        )
                )
            } else {
                // Measurement tool selection
                MeasurementToolButton(
                    icon: "ruler",
                    label: "Distance",
                    key: "d",
                    action: { measurementSystem.startMeasurement(type: .distance) }
                )

                MeasurementToolButton(
                    icon: "angle",
                    label: "Angle",
                    key: "a",
                    action: { measurementSystem.startMeasurement(type: .angle) }
                )

                MeasurementToolButton(
                    icon: "circle",
                    label: "Radius",
                    key: "c",
                    action: { measurementSystem.startMeasurement(type: .radius) }
                )
            }

            // Show Clear All button if measurements exist
            if !measurementSystem.measurements.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.vertical, 2)

                Button(action: { measurementSystem.clearAll() }) {
                    HStack(spacing: 4) {
                        Spacer()
                        Image(systemName: "trash")
                            .font(.system(size: 8))
                        Text("Clear All")
                            .font(.system(size: 9))
                        KeyHint(key: "c")
                        Spacer()
                    }
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.red.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func modeLabel(_ mode: MeasurementType) -> String {
        switch mode {
        case .distance: return "Distance"
        case .angle: return "Angle"
        case .radius: return "Radius"
        }
    }

    private func formatDistance(_ value: Double) -> String {
        if value < 1.0 {
            return String(format: "%.2f mm", value)
        } else if value < 100.0 {
            return String(format: "%.1f mm", value)
        } else {
            return String(format: "%.0f mm", value)
        }
    }
}

// MARK: - Helper Views

struct CameraPresetButton: View {
    let label: String
    let key: String
    let preset: CameraPreset
    let camera: Camera

    var body: some View {
        Button(action: { camera.setPreset(preset) }) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.8))
                KeyHint(key: key)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

struct MeasurementToolButton: View {
    let icon: String
    let label: String
    let key: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                KeyHint(key: key)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

/// A single row of information
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.8))
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

/// A small keyboard key hint badge
struct KeyHint: View {
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
    let appState = AppState()
    let model = STLModel(
        triangles: [
            Triangle(
                v1: Vector3(0, 0, 0),
                v2: Vector3(10, 0, 0),
                v3: Vector3(5, 10, 0)
            )
        ],
        name: "test-model"
    )
    appState.modelInfo = ModelInfo(fileName: "test-model.stl", model: model)

    return ZStack {
        Color.gray
        MainMenuPanel(appState: appState)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
