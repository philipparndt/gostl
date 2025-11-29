import SwiftUI
import Observation
import Metal

@Observable
final class AppState: @unchecked Sendable {
    /// Clear color for the background (dark blue matching Go version: RGB 15, 18, 25)
    var clearColor: SIMD4<Float> = SIMD4(0.059, 0.071, 0.098, 1.0)

    /// Camera for 3D navigation
    var camera = Camera()

    /// Currently loaded STL model
    var model: STLModel?

    /// Information about the loaded model
    var modelInfo: ModelInfo?

    /// GPU mesh data for rendering
    var meshData: MeshData?

    /// GPU wireframe data for edge rendering
    var wireframeData: WireframeData?

    /// GPU grid data for spatial reference
    var gridData: GridData?

    /// GPU measurement data for rendering measurements
    var measurementData: MeasurementRenderData?

    /// Whether to show wireframe overlay
    var showWireframe: Bool = true

    /// Whether to show grid
    var showGrid: Bool = true

    /// Whether to show model info overlay
    var showModelInfo: Bool = true

    /// Measurement system for distance/angle/radius measurements
    var measurementSystem = MeasurementSystem()

    init() {}

    /// Initialize grid
    func initializeGrid(device: MTLDevice) throws {
        self.gridData = try GridData(device: device, size: 100.0, spacing: 10.0)
    }

    /// Initialize measurement rendering
    func initializeMeasurements(device: MTLDevice) {
        self.measurementData = MeasurementRenderData(device: device)
    }

    /// Load an STL model and create mesh data for rendering
    func loadModel(_ model: STLModel, device: MTLDevice) throws {
        self.model = model
        self.meshData = try MeshData(device: device, model: model)

        // Calculate wireframe thickness based on model size
        let bbox = model.boundingBox()
        let modelSize = bbox.diagonal
        let thickness = Float(modelSize) * 0.002 // 0.2% of model size
        self.wireframeData = try WireframeData(device: device, model: model, thickness: thickness)

        // Frame the model in view
        camera.frameBoundingBox(bbox)

        // Clear all measurements when loading a new model
        measurementSystem.clearAll()
    }

    /// Load an STL file from URL
    func loadFile(_ url: URL, device: MTLDevice) throws {
        print("Loading STL file: \(url.lastPathComponent)")
        let model = try STLParser.parse(url: url)
        try loadModel(model, device: device)
        self.modelInfo = ModelInfo(fileName: url.lastPathComponent, model: model)
        print("Successfully loaded: \(model.triangleCount) triangles")
    }

    /// Cycle to the next material type
    func cycleMaterial() {
        if var info = modelInfo {
            info.material = info.material.next()
            self.modelInfo = info
            print("Material changed to: \(info.material.rawValue)")
        }
    }
}
