import SwiftUI
import Metal
import AppKit

struct ContentView: View {
    @State private var appState = AppState()
    @State private var errorAlert: ErrorAlert?
    @State private var showErrorOverlay = false
    @State private var windowTitle: String = "GoSTL"

    let fileURL: URL?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        // Notifications are set up in onAppear since we need access to appState
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MetalView(appState: appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                // Measurement labels (in 3D space)
                MeasurementLabelsOverlay(
                    measurementSystem: appState.measurementSystem,
                    camera: appState.camera,
                    viewSize: geometry.size
                )

                // Selection rectangle overlay
                SelectionRectangleOverlay(measurementSystem: appState.measurementSystem)

                // Main menu panel (top-left)
                if appState.showModelInfo {
                    VStack {
                        HStack {
                            MainMenuPanel(appState: appState)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // Slicing panel (bottom-right)
                if appState.slicingState.isVisible {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            SlicingPanel(slicingState: appState.slicingState)
                                .padding(12)
                        }
                    }
                }

                // Leveling panel (bottom-right, replaces slicing when active)
                if appState.levelingState.isActive {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            LevelingPanel(
                                levelingState: appState.levelingState,
                                onApply: { axis in
                                    appState.levelingState.selectAxis(axis)
                                    applyLeveling()
                                },
                                onCancel: {
                                    appState.levelingState.reset()
                                },
                                onUndo: {
                                    guard let device = MTLCreateSystemDefaultDevice() else { return }
                                    try? appState.undoLeveling(device: device)
                                }
                            )
                            .padding(12)
                        }
                    }
                }

                // Plate selector (bottom-center) - only shown for 3MF files with multiple plates
                if appState.hasMultiplePlates {
                    VStack {
                        Spacer()
                        PlateSelector(appState: appState)
                            .padding(.bottom, 16)
                    }
                }

                // Loading overlay (shown while waiting for file to load)
                if appState.isLoading {
                    LoadingOverlay()
                        .transition(.opacity)
                }

                // Background processing indicator (shown while spatial index or wireframe builds)
                if (appState.isBuildingAccelerator || appState.isBuildingWireframe) && !appState.isLoading {
                    VStack {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                            VStack(alignment: .leading, spacing: 2) {
                                if appState.isBuildingWireframe {
                                    Text("Building wireframe...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if appState.isBuildingAccelerator {
                                    Text("Building spatial index...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 50)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeInOut(duration: 0.3), value: appState.isBuildingAccelerator || appState.isBuildingWireframe)
                }

                // Empty file indicator (shown when OpenSCAD file has no geometry)
                if appState.isEmptyFile {
                    EmptyFileOverlay(fileName: appState.modelInfo?.fileName ?? "")
                }

                // Error overlay (shown for auto-reload errors)
                if showErrorOverlay, let error = appState.loadError as? OpenSCADError {
                    ErrorOverlay(error: error) {
                        showErrorOverlay = false
                        appState.loadError = nil
                        appState.loadErrorID = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .navigationTitle(windowTitle)
        .focusedSceneValue(\.appState, appState)
        .onAppear {
            setupNotifications()

            // Initialize rendering components
            if let device = MTLCreateSystemDefaultDevice() {
                do {
                    try appState.initializeGrid(device: device)
                    appState.initializeMeasurements(device: device)
                    appState.initializeOrientationCube(device: device)
                } catch {
                    print("ERROR: Failed to initialize rendering: \(error)")
                }
            }

            // Load file if provided via command line or init parameter
            if let fileURL = fileURL {
                loadFileOnStartup(fileURL)
            } else {
                // No file - show test cube
                setupInitialState(loadTestCube: true)
            }
        }
        .onOpenURL { url in
            // Handle files opened via Finder (double-click, Open With, etc.)
            let ext = url.pathExtension.lowercased()
            guard ["stl", "3mf", "scad", "yaml", "yml"].contains(ext) else { return }

            guard let device = MTLCreateSystemDefaultDevice() else { return }

            appState.isLoading = true
            Task { @MainActor in
                do {
                    try appState.loadFile(url, device: device)
                    windowTitle = url.lastPathComponent

                    if let window = NSApp.keyWindow {
                        window.representedURL = url
                        window.title = url.lastPathComponent
                    }

                    RecentDocuments.shared.addDocument(url)
                    try? appState.setupFileWatcher()
                } catch {
                    print("ERROR: Failed to load file: \(error)")
                    appState.isLoading = false
                }
            }
        }
        .onChange(of: appState.slicingState.bounds) { _, _ in
            updateSlicedMesh()
        }
        .onChange(of: appState.slicingState.isVisible) { _, _ in
            updateSlicedMesh()
        }
        .onChange(of: appState.slicingState.showPlanes) { _, newValue in
            // Only update mesh if planes are being turned on (need to create slice plane data)
            // Turning off doesn't require mesh update
            if newValue {
                updateSlicedMesh()
            } else {
                // Just clear slice plane data without full mesh update
                appState.slicePlaneData = nil
            }
        }
        .onChange(of: appState.slicingState.activePlane != nil) { _, _ in
            // Only update slice plane visualization, not the whole mesh
            updateSlicePlaneOnly()
        }
        .onChange(of: appState.reloadRequestId) { _, _ in
            reloadModel()
        }
        .onChange(of: appState.loadErrorID) { _, errorID in
            if let error = appState.loadError {
                handleLoadError(error, isAutoReload: true)
            } else if errorID == nil {
                // Error was cleared (successful reload), dismiss overlay
                withAnimation(.easeInOut(duration: 0.3)) {
                    showErrorOverlay = false
                }
            }
        }
        .alert(item: $errorAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func updateSlicedMesh() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        do {
            try appState.updateMeshData(device: device)
        } catch {
            print("ERROR: Failed to update sliced mesh: \(error)")
        }
    }

    private func applyLeveling() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        do {
            try appState.applyLevelingRotation(device: device)
        } catch {
            print("ERROR: Failed to apply leveling: \(error)")
        }
    }

    private func updateSlicePlaneOnly() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let model = appState.model else { return }
        do {
            // Only update slice plane visualization without recalculating mesh
            if appState.slicingState.showPlanes && appState.slicingState.activePlane != nil {
                let bbox = model.boundingBox()
                let planeSize = Float(bbox.diagonal * 1.5)
                appState.slicePlaneData = try SlicePlaneData(
                    device: device,
                    slicingState: appState.slicingState,
                    modelCenter: bbox.center,
                    planeSize: planeSize
                )
            } else {
                appState.slicePlaneData = nil
            }
        } catch {
            print("ERROR: Failed to update slice plane: \(error)")
        }
    }

    private func loadFileOnStartup(_ url: URL) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ERROR: Metal device not available")
            return
        }

        appState.isLoading = true
        Task { @MainActor in
            do {
                try appState.loadFile(url, device: device)
                windowTitle = url.lastPathComponent

                if let window = NSApp.keyWindow {
                    window.representedURL = url
                    window.title = url.lastPathComponent
                }

                RecentDocuments.shared.addDocument(url)
                try? appState.setupFileWatcher()
            } catch {
                print("ERROR: Failed to load file on startup: \(error)")
                handleLoadError(error, isAutoReload: false)
                setupInitialState(loadTestCube: true)
            }
        }
    }

    private func setupNotifications() {
        // Set up menu command notifications (reload, etc.)
        // File loading is handled via onOpenURL modifier
    }

    private func reloadModel() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        appState.reloadModel(device: device)
    }

    private func handleLoadError(_ error: Error, isAutoReload: Bool) {
        if let openscadError = error as? OpenSCADError {
            // For auto-reload errors, show overlay instead of modal dialog
            if isAutoReload {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showErrorOverlay = true
                }
            } else {
                // For initial load errors, show modal dialog
                switch openscadError {
                case .openSCADNotFound:
                    errorAlert = ErrorAlert(
                        title: "OpenSCAD Not Installed",
                        message: "OpenSCAD is required to render .scad files.\n\nPlease install OpenSCAD from:\nhttps://openscad.org/downloads.html\n\nOr install via Homebrew:\nbrew install --cask openscad"
                    )
                case .renderFailed(let message):
                    errorAlert = ErrorAlert(
                        title: "OpenSCAD Render Failed",
                        message: message
                    )
                case .emptyFile:
                    // Empty files are handled gracefully - no error dialog needed
                    break
                }
            }
        } else {
            // For non-OpenSCAD errors, always show modal dialog
            errorAlert = ErrorAlert(
                title: "Failed to Load File",
                message: error.localizedDescription
            )
        }
    }

    private func setupInitialState(loadTestCube: Bool = true) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ERROR: Metal device not available")
            return
        }

        do {
            // Load test cube if requested
            if loadTestCube {
                let testCube = createTestCube()
                try appState.loadModel(testCube, device: device)
                appState.modelInfo = ModelInfo(fileName: "test_cube.stl", model: testCube)
                print("Test cube loaded: \(testCube.triangleCount) triangles")
            }
        } catch {
            print("ERROR: Failed to initialize scene: \(error)")
        }
    }

    // Create a simple test cube (10x10x10 centered at origin)
    private func createTestCube() -> STLModel {
        var triangles: [Triangle] = []
        let size: Double = 50.0
        let half = size / 2.0

        // Bottom face (z = -half)
        triangles.append(Triangle(v1: Vector3(-half, -half, -half), v2: Vector3(half, half, -half), v3: Vector3(half, -half, -half)))
        triangles.append(Triangle(v1: Vector3(-half, -half, -half), v2: Vector3(-half, half, -half), v3: Vector3(half, half, -half)))

        // Top face (z = half)
        triangles.append(Triangle(v1: Vector3(-half, -half, half), v2: Vector3(half, -half, half), v3: Vector3(half, half, half)))
        triangles.append(Triangle(v1: Vector3(-half, -half, half), v2: Vector3(half, half, half), v3: Vector3(-half, half, half)))

        // Front face (y = -half)
        triangles.append(Triangle(v1: Vector3(-half, -half, -half), v2: Vector3(half, -half, -half), v3: Vector3(half, -half, half)))
        triangles.append(Triangle(v1: Vector3(-half, -half, -half), v2: Vector3(half, -half, half), v3: Vector3(-half, -half, half)))

        // Back face (y = half)
        triangles.append(Triangle(v1: Vector3(-half, half, -half), v2: Vector3(half, half, half), v3: Vector3(half, half, -half)))
        triangles.append(Triangle(v1: Vector3(-half, half, -half), v2: Vector3(-half, half, half), v3: Vector3(half, half, half)))

        // Left face (x = -half)
        triangles.append(Triangle(v1: Vector3(-half, -half, -half), v2: Vector3(-half, -half, half), v3: Vector3(-half, half, half)))
        triangles.append(Triangle(v1: Vector3(-half, -half, -half), v2: Vector3(-half, half, half), v3: Vector3(-half, half, -half)))

        // Right face (x = half)
        triangles.append(Triangle(v1: Vector3(half, -half, -half), v2: Vector3(half, half, -half), v3: Vector3(half, half, half)))
        triangles.append(Triangle(v1: Vector3(half, -half, -half), v2: Vector3(half, half, half), v3: Vector3(half, -half, half)))

        return STLModel(triangles: triangles, name: "test_cube")
    }
}

/// Error alert for displaying user-friendly error messages
struct ErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Loading overlay shown while waiting for file to load
struct LoadingOverlay: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)

            Text("Loading...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        )
    }
}

/// Overlay shown when an OpenSCAD file produces no geometry
struct EmptyFileOverlay: View {
    let fileName: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.6))

            Text("Empty Model")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text("The file produces no geometry")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
        )
    }
}

#Preview {
    ContentView()
}
