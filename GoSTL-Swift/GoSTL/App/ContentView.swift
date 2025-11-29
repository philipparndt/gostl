import SwiftUI
import Metal

struct ContentView: View {
    @State private var appState = AppState()

    init() {
        print("DEBUG: ContentView initializing...")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalView(appState: appState)

            // Model info overlay (top-left)
            if appState.showModelInfo, let modelInfo = appState.modelInfo {
                ModelInfoOverlay(modelInfo: modelInfo)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            loadTestModel()
            setupNotifications()
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LoadSTLFile"),
            object: nil,
            queue: .main
        ) { [weak appState] notification in
            guard let appState,
                  let url = notification.object as? URL,
                  let device = MTLCreateSystemDefaultDevice() else {
                return
            }

            Task { @MainActor in
                do {
                    try appState.loadFile(url, device: device)
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

    // Create a simple test cube (1x1x1 at origin)
    private func createTestCube() -> STLModel {
        var triangles: [Triangle] = []

        // Bottom face (z = 0)
        triangles.append(Triangle(v1: Vector3(0, 0, 0), v2: Vector3(1, 1, 0), v3: Vector3(1, 0, 0)))
        triangles.append(Triangle(v1: Vector3(0, 0, 0), v2: Vector3(0, 1, 0), v3: Vector3(1, 1, 0)))

        // Top face (z = 1)
        triangles.append(Triangle(v1: Vector3(0, 0, 1), v2: Vector3(1, 0, 1), v3: Vector3(1, 1, 1)))
        triangles.append(Triangle(v1: Vector3(0, 0, 1), v2: Vector3(1, 1, 1), v3: Vector3(0, 1, 1)))

        // Front face (y = 0)
        triangles.append(Triangle(v1: Vector3(0, 0, 0), v2: Vector3(1, 0, 0), v3: Vector3(1, 0, 1)))
        triangles.append(Triangle(v1: Vector3(0, 0, 0), v2: Vector3(1, 0, 1), v3: Vector3(0, 0, 1)))

        // Back face (y = 1)
        triangles.append(Triangle(v1: Vector3(0, 1, 0), v2: Vector3(1, 1, 1), v3: Vector3(1, 1, 0)))
        triangles.append(Triangle(v1: Vector3(0, 1, 0), v2: Vector3(0, 1, 1), v3: Vector3(1, 1, 1)))

        // Left face (x = 0)
        triangles.append(Triangle(v1: Vector3(0, 0, 0), v2: Vector3(0, 0, 1), v3: Vector3(0, 1, 1)))
        triangles.append(Triangle(v1: Vector3(0, 0, 0), v2: Vector3(0, 1, 1), v3: Vector3(0, 1, 0)))

        // Right face (x = 1)
        triangles.append(Triangle(v1: Vector3(1, 0, 0), v2: Vector3(1, 1, 0), v3: Vector3(1, 1, 1)))
        triangles.append(Triangle(v1: Vector3(1, 0, 0), v2: Vector3(1, 1, 1), v3: Vector3(1, 0, 1)))

        return STLModel(triangles: triangles, name: "test_cube")
    }
}

#Preview {
    ContentView()
}
