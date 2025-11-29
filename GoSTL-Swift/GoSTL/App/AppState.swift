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

    /// GPU slice plane data for visualizing slice boundaries
    var slicePlaneData: SlicePlaneData?

    /// GPU cut edge data for rendering sliced edges in axis colors
    var cutEdgeData: CutEdgeData?

    /// Whether to show wireframe overlay
    var showWireframe: Bool = true

    /// Whether to show grid
    var showGrid: Bool = true

    /// Whether to show model info overlay
    var showModelInfo: Bool = true

    /// Measurement system for distance/angle/radius measurements
    var measurementSystem = MeasurementSystem()

    /// Slicing system for clipping model along axes
    var slicingState = SlicingState()

    init() {}

    /// Initialize grid
    func initializeGrid(device: MTLDevice) throws {
        self.gridData = try GridData(device: device, size: 100.0, spacing: 10.0)
    }

    /// Initialize measurement rendering
    func initializeMeasurements(device: MTLDevice, thickness: Float = 0.01) {
        do {
            self.measurementData = try MeasurementRenderData(device: device, thickness: thickness)
        } catch {
            print("ERROR: Failed to create measurement data: \(error)")
        }
    }

    /// Update mesh data based on current slicing bounds
    func updateMeshData(device: MTLDevice) throws {
        guard let model else { return }

        // Calculate wireframe thickness based on model size
        let bbox = model.boundingBox()
        let modelSize = bbox.diagonal
        let thickness = Float(modelSize) * 0.002

        // If slicing is active, use triangle slicer to clip geometry
        if slicingState.isVisible {
            let slicedResult = TriangleSlicer.sliceTriangles(model.triangles, bounds: slicingState.bounds)

            // Only create mesh data if we have triangles
            if !slicedResult.triangles.isEmpty {
                let slicedModel = STLModel(triangles: slicedResult.triangles, name: model.name)
                self.meshData = try MeshData(device: device, model: slicedModel)
                // Create wireframe from ORIGINAL model edges, clipped to bounds (preserves edge directions)
                self.wireframeData = try WireframeData(device: device, model: model, thickness: thickness, sliceBounds: slicingState.bounds)
            } else {
                // No triangles in bounds - don't render mesh or wireframe
                self.meshData = nil
                self.wireframeData = nil
            }

            // Create cut edge visualization
            if !slicedResult.cutEdges.isEmpty {
                self.cutEdgeData = try CutEdgeData(device: device, cutEdges: slicedResult.cutEdges)
            } else {
                self.cutEdgeData = nil
            }

            // Create slice plane visualization
            // Show planes ONLY if: toggle is on AND a slider is being actively dragged
            if slicingState.showPlanes && slicingState.activePlane != nil {
                let planeSize = Float(bbox.diagonal * 1.5)  // Make planes larger than model
                self.slicePlaneData = try SlicePlaneData(
                    device: device,
                    slicingState: slicingState,
                    modelCenter: bbox.center,
                    planeSize: planeSize
                )
            } else {
                self.slicePlaneData = nil
            }
        } else {
            // Show full model
            self.meshData = try MeshData(device: device, model: model)
            self.wireframeData = try WireframeData(device: device, model: model, thickness: thickness)
            self.slicePlaneData = nil
            self.cutEdgeData = nil
        }
    }

    /// Load an STL model and create mesh data for rendering
    func loadModel(_ model: STLModel, device: MTLDevice) throws {
        self.model = model
        try updateMeshData(device: device)

        // Calculate wireframe thickness based on model size
        let bbox = model.boundingBox()
        let modelSize = bbox.diagonal
        let thickness = Float(modelSize) * 0.002 // 0.2% of model size
        self.wireframeData = try WireframeData(device: device, model: model, thickness: thickness)

        // Reinitialize measurement data with appropriate thickness for this model
        initializeMeasurements(device: device, thickness: thickness)

        // Frame the model in view
        camera.frameBoundingBox(bbox)

        // Initialize slicing bounds
        slicingState.initializeBounds(from: bbox)

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
