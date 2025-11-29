import SwiftUI
import Metal

struct ContentView: View {
    @State private var appState = AppState()

    init() {
        print("DEBUG: ContentView initializing...")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MetalView(appState: appState)

                // Measurement labels (in 3D space)
                MeasurementLabelsOverlay(
                    measurementSystem: appState.measurementSystem,
                    camera: appState.camera,
                    viewSize: geometry.size
                )

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
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            loadTestModel()
            setupNotifications()
        }
        .onChange(of: appState.slicingState.bounds) { _, _ in
            updateSlicedMesh()
        }
        .onChange(of: appState.slicingState.isVisible) { _, _ in
            updateSlicedMesh()
        }
        .onChange(of: appState.slicingState.showPlanes) { _, _ in
            updateSlicedMesh()
        }
        .onChange(of: appState.slicingState.activePlane?.axis) { _, _ in
            updateSlicedMesh()
        }
        .onChange(of: appState.slicingState.activePlane?.isMin) { _, _ in
            updateSlicedMesh()
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

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LoadSTLFile"),
            object: nil,
            queue: .main
        ) { [appState] notification in
            guard let url = notification.object as? URL,
                  let device = MTLCreateSystemDefaultDevice() else {
                return
            }

            Task { @MainActor in
                do {
                    try appState.loadFile(url, device: device)
                    // Add to recent documents after successful load
                    RecentDocuments.shared.addDocument(url)
                } catch {
                    print("ERROR: Failed to load file: \(error)")
                    // TODO: Show error alert to user
                }
            }
        }
    }

    private func loadTestModel() {
        // Create a test cube to verify rendering works
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ERROR: Metal device not available")
            return
        }

        do {
            // Initialize grid
            try appState.initializeGrid(device: device)
            print("Grid initialized")

            // Initialize measurements
            appState.initializeMeasurements(device: device)
            print("Measurements initialized")

            // Load test cube
            let testCube = createTestCube()
            try appState.loadModel(testCube, device: device)
            appState.modelInfo = ModelInfo(fileName: "test_cube.stl", model: testCube)
            print("Test cube loaded: \(testCube.triangleCount) triangles")
            if let wireframeData = appState.wireframeData {
                print("Wireframe data created: \(wireframeData.instanceCount) edges")
            } else {
                print("WARNING: No wireframe data created")
            }
        } catch {
            print("ERROR: Failed to initialize scene: \(error)")
        }
    }

    // Create a simple test cube (10x10x10 centered at origin)
    private func createTestCube() -> STLModel {
        var triangles: [Triangle] = []
        let size: Double = 10.0
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

#Preview {
    ContentView()
}
