import SwiftUI
import Observation
import Metal

@Observable
final class AppState {
    /// Clear color for the background (dark blue matching Go version: RGB 15, 18, 25)
    var clearColor: SIMD4<Float> = SIMD4(0.059, 0.071, 0.098, 1.0)

    /// Camera for 3D navigation
    var camera = Camera()

    /// Currently loaded STL model
    var model: STLModel?

    /// GPU mesh data for rendering
    var meshData: MeshData?

    /// GPU wireframe data for edge rendering
    var wireframeData: WireframeData?

    /// Whether to show wireframe overlay
    var showWireframe: Bool = true

    init() {}

    /// Load an STL model and create mesh data for rendering
    func loadModel(_ model: STLModel, device: MTLDevice) throws {
        self.model = model
        self.meshData = try MeshData(device: device, model: model)
        self.wireframeData = try WireframeData(device: device, model: model)

        // Frame the model in view
        let bbox = model.boundingBox()
        camera.frameBoundingBox(bbox)
    }
}
