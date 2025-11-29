import SwiftUI
import Metal

struct ContentView: View {
    @State private var appState = AppState()

    init() {
        print("DEBUG: ContentView initializing...")
    }

    var body: some View {
        MetalView(appState: appState)
            .frame(minWidth: 800, minHeight: 600)
            .onAppear {
                loadTestModel()
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
            print("Test cube loaded: \(testCube.triangleCount) triangles")
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
