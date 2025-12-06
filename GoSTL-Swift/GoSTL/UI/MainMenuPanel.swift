import SwiftUI
import Metal

/// Main menu panel with Info, View, and Tools sections
struct MainMenuPanel: View {
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Info Section
            if let modelInfo = appState.modelInfo {
                MenuSection(title: "Info", icon: "info.circle") {
                    InfoSectionContent(
                        modelInfo: modelInfo,
                        slicingState: appState.slicingState,
                        visibleTriangleCount: (appState.meshData?.vertexCount ?? 0) / 3
                    )
                }
            }

            // View Section
            MenuSection(title: "View", icon: "eye") {
                ViewSectionContent(appState: appState)
            }

            // Tools Section
            MenuSection(title: "Tools", icon: "ruler") {
                ToolsSectionContent(measurementSystem: appState.measurementSystem, appState: appState)
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
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
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
    let slicingState: SlicingState
    let visibleTriangleCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // File name
            Text(modelInfo.fileName)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)

            // Triangle count (with slicing info if active)
            if slicingState.isVisible {
                HStack(spacing: 4) {
                    Text("Triangles:")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                    Text("\(ModelInfo.formatCount(visibleTriangleCount))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.orange)
                    Text("/ \(ModelInfo.formatCount(modelInfo.triangleCount))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                HStack(spacing: 4) {
                    Image(systemName: "scissors")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                    Text("Slicing active")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                    KeyHint(key: "⇧S")
                }
            } else {
                InfoRow(label: "Triangles:", value: ModelInfo.formatCount(modelInfo.triangleCount))
            }

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
            // Wireframe mode
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Wireframe:")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                    KeyHint(key: "w")
                }

                HStack(spacing: 3) {
                    WireframeModeRadio(mode: .off, label: "Off", currentMode: appState.wireframeMode, appState: appState)
                    WireframeModeRadio(mode: .all, label: "All", currentMode: appState.wireframeMode, appState: appState)
                    WireframeModeRadio(mode: .edge, label: "Edge", currentMode: appState.wireframeMode, appState: appState)
                }

            }

            // Grid mode
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Grid:")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                    KeyHint(key: "g")
                }

                HStack(spacing: 3) {
                    GridModeRadio(mode: .off, label: "Off", currentMode: appState.gridMode, appState: appState)
                    GridModeRadio(mode: .bottom, label: "Bottom", currentMode: appState.gridMode, appState: appState)
                    GridModeRadio(mode: .allSides, label: "All", currentMode: appState.gridMode, appState: appState)
                    GridModeRadio(mode: .oneMM, label: "1mm", currentMode: appState.gridMode, appState: appState)
                }
            }

            // Slicing toggle
            HStack(spacing: 4) {
                Button(action: { appState.slicingState.toggleVisibility() }) {
                    HStack(spacing: 4) {
                        Image(systemName: appState.slicingState.isVisible ? "checkmark.square.fill" : "square")
                            .font(.system(size: 10))
                            .foregroundColor(appState.slicingState.isVisible ? .orange : .white.opacity(0.5))
                        Text("Slicing")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                KeyHint(key: "⇧S")
            }

            // Build plate selector
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Build Plate:")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                    BuildPlatePicker(currentPlate: appState.buildPlate, appState: appState)
                    KeyHint(key: "⌘B")
                }

                // Orientation toggle (only show when build plate is active)
                if appState.buildPlate != .off {
                    HStack(spacing: 4) {
                        Text("Orientation:")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                        BuildPlateOrientationToggle(orientation: appState.buildPlateOrientation, appState: appState)
                    }
                }
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
                HStack(spacing: 3) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9))
                    Text("Reset View")
                        .font(.system(size: 10))
                    Spacer()
                    KeyHint(key: "ESC")
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
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
    var appState: AppState?

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
                        if let constraint = measurementSystem.constraint {
                            Text("(\(constraintLabel(constraint)))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(constraintColor(constraint))
                        }
                    }

                    Text("Points: \(measurementSystem.pointsNeededText)")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.8))

                    Text("Click on model vertices")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                        .italic()

                    if mode == .distance {
                        // Show constraint hint when at least one point is selected
                        if !measurementSystem.currentPoints.isEmpty {
                            if measurementSystem.constraint != nil {
                                HStack(spacing: 4) {
                                    KeyHint(key: "⌥")
                                    Text("Release constraint")
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("X/Y/Z: constrain to axis")
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.5))
                                    HStack(spacing: 4) {
                                        KeyHint(key: "⌥")
                                        Text("Constrain to direction")
                                            .font(.system(size: 9))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }
                            }
                        }

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
                    key: "r",
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

            // Open with go3mf button
            if appState?.sourceFileURL != nil {
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.vertical, 2)

                Button(action: {
                    openWithGo3mf(sourceFileURL: appState?.sourceFileURL)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 16)
                        Text("Open with go3mf")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        KeyHint(key: "o")
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
    }

    private func modeLabel(_ mode: MeasurementType) -> String {
        switch mode {
        case .distance: return "Distance"
        case .angle: return "Angle"
        case .radius: return "Radius"
        }
    }

    private func constraintAxisName(_ constraint: ConstraintType) -> String {
        switch constraint {
        case .axis(let axis):
            return ["X", "Y", "Z"][axis]
        case .point:
            return "Point"
        }
    }

    private func constraintAxisColor(_ constraint: ConstraintType) -> Color {
        switch constraint {
        case .axis(let axis):
            switch axis {
            case 0: return Color.red      // X axis
            case 1: return Color.green    // Y axis
            case 2: return Color.blue     // Z axis
            default: return Color.white
            }
        case .point:
            return Color.cyan
        }
    }

    private func constraintLabel(_ constraint: ConstraintType) -> String {
        switch constraint {
        case .axis(let axis):
            return ["X", "Y", "Z"][axis]
        case .point:
            return "→"  // Arrow to indicate direction constraint
        }
    }

    private func constraintColor(_ constraint: ConstraintType) -> Color {
        switch constraint {
        case .axis(let axis):
            switch axis {
            case 0: return Color.red
            case 1: return Color.green
            case 2: return Color.blue
            default: return Color.white
            }
        case .point:
            return Color.cyan
        }
    }
}

// MARK: - Helper Views

struct GridModeRadio: View {
    let mode: GridMode
    let label: String
    let currentMode: GridMode
    let appState: AppState

    var body: some View {
        Button(action: {
            appState.gridMode = mode
            if let device = MTLCreateSystemDefaultDevice() {
                try? appState.updateGrid(device: device)
            }
        }) {
            HStack(spacing: 2) {
                Image(systemName: currentMode == mode ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .foregroundColor(currentMode == mode ? .blue : .white.opacity(0.5))
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(currentMode == mode ? Color.blue.opacity(0.2) : Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

struct WireframeModeRadio: View {
    let mode: WireframeMode
    let label: String
    let currentMode: WireframeMode
    let appState: AppState

    var body: some View {
        Button(action: {
            appState.wireframeMode = mode
            if let device = MTLCreateSystemDefaultDevice() {
                try? appState.updateWireframe(device: device)
            }
        }) {
            HStack(spacing: 2) {
                Image(systemName: currentMode == mode ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .foregroundColor(currentMode == mode ? .blue : .white.opacity(0.5))
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(currentMode == mode ? Color.blue.opacity(0.2) : Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

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
                Spacer()
                KeyHint(key: key)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
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

/// Build plate picker with dropdown menu
struct BuildPlatePicker: View {
    let currentPlate: BuildPlate
    let appState: AppState

    var body: some View {
        Menu {
            Button("Off") {
                setBuildPlate(.off)
            }

            Divider()

            // Bambu Lab
            Menu("Bambu Lab") {
                Button("X1C (256³)") { setBuildPlate(.bambuLabX1C) }
                Button("P1S (256³)") { setBuildPlate(.bambuLabP1S) }
                Button("A1 (256³)") { setBuildPlate(.bambuLabA1) }
                Button("A1 mini (180³)") { setBuildPlate(.bambuLabA1Mini) }
                Button("H2D (450³)") { setBuildPlate(.bambuLabH2D) }
            }

            // Prusa
            Menu("Prusa") {
                Button("MK4 (250x210x220)") { setBuildPlate(.prusa_mk4) }
                Button("Mini (180³)") { setBuildPlate(.prusa_mini) }
            }

            // Voron
            Menu("Voron") {
                Button("V0 (120³)") { setBuildPlate(.voron_v0) }
                Button("2.4 (350³)") { setBuildPlate(.voron_24) }
            }

            // Creality
            Menu("Creality") {
                Button("Ender 3 (220x220x250)") { setBuildPlate(.ender3) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentPlate == .off ? "Off" : currentPlate.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(currentPlate != .off ? Color.blue.opacity(0.2) : Color.white.opacity(0.1))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func setBuildPlate(_ plate: BuildPlate) {
        appState.buildPlate = plate
        if let device = MTLCreateSystemDefaultDevice() {
            appState.updateBuildPlate(device: device)
        }
    }
}

/// Toggle for build plate orientation (Bottom/Back)
struct BuildPlateOrientationToggle: View {
    let orientation: BuildPlateOrientation
    let appState: AppState

    var body: some View {
        HStack(spacing: 2) {
            ForEach(BuildPlateOrientation.allCases, id: \.self) { opt in
                Button(action: { setOrientation(opt) }) {
                    Text(opt.displayName)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(orientation == opt ? 1.0 : 0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(orientation == opt ? Color.blue.opacity(0.3) : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func setOrientation(_ newOrientation: BuildPlateOrientation) {
        appState.buildPlateOrientation = newOrientation
        if let device = MTLCreateSystemDefaultDevice() {
            appState.updateBuildPlate(device: device)
        }
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
