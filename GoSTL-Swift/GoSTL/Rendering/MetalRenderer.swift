import Metal
import MetalKit

final class MetalRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let meshPipelineState: MTLRenderPipelineState
    let wireframePipelineState: MTLRenderPipelineState
    let gridPipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState

    init(device: MTLDevice) throws {
        print("DEBUG: Initializing MetalRenderer...")
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            print("DEBUG: Failed to create command queue")
            throw MetalError.commandQueueCreationFailed
        }
        self.commandQueue = queue

        // Create rendering pipelines
        self.meshPipelineState = try Self.createMeshPipeline(device: device)
        self.wireframePipelineState = try Self.createWireframePipeline(device: device)
        self.gridPipelineState = try Self.createGridPipeline(device: device)

        // Create depth stencil state
        self.depthStencilState = Self.createDepthStencilState(device: device)

        print("DEBUG: MetalRenderer initialized successfully")
    }

    // MARK: - Pipeline Creation

    private static func createMeshPipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
        // Load shader source and compile
        let library = try loadShaderLibrary(device: device)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "meshVertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "meshFragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        // Vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        // Position (attribute 0)
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // Normal (attribute 1)
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        // Color (attribute 2)
        vertexDescriptor.attributes[2].format = .float4
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        // Layout
        vertexDescriptor.layouts[0].stride = MemoryLayout<VertexIn>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    private static func createWireframePipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
        let library = try loadShaderLibrary(device: device)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "wireframeVertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "wireframeFragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        // Use same vertex descriptor as mesh
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float4
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<VertexIn>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    private static func createGridPipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
        let library = try loadShaderLibrary(device: device)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "gridVertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "gridFragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        // Enable alpha blending for grid fade
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add

        // Same vertex descriptor as mesh
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float4
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<VertexIn>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    private static func createDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: depthDescriptor)!
    }

    private static func loadShaderLibrary(device: MTLDevice) throws -> MTLLibrary {
        // For SPM builds, load from the module bundle
        let bundle = Bundle.module

        // Look for the compiled Metal library (default.metallib)
        guard let libraryURL = bundle.url(forResource: "default", withExtension: "metallib") else {
            print("DEBUG: Failed to find default.metallib in bundle: \(bundle.bundlePath)")
            throw MetalError.shaderLoadingFailed
        }

        print("DEBUG: Loading Metal library from: \(libraryURL.path)")
        return try device.makeLibrary(URL: libraryURL)
    }

    @MainActor
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Will be used for aspect ratio calculations in later phases
    }

    private var frameCount = 0

    @MainActor
    func draw(in view: MTKView, appState: AppState) {
        frameCount += 1

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }

        // Set clear color (dark blue: RGB 15, 18, 25)
        if let colorAttachment = renderPassDescriptor.colorAttachments[0] {
            colorAttachment.loadAction = .clear
            colorAttachment.clearColor = MTLClearColor(
                red: Double(appState.clearColor.x),
                green: Double(appState.clearColor.y),
                blue: Double(appState.clearColor.z),
                alpha: Double(appState.clearColor.w)
            )
        }

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // Render grid first (background)
        if appState.showGrid, let gridData = appState.gridData {
            renderGrid(encoder: renderEncoder, gridData: gridData, appState: appState, viewSize: view.drawableSize)
        }

        // Render mesh if available
        if let meshData = appState.meshData {
            renderMesh(encoder: renderEncoder, meshData: meshData, appState: appState, viewSize: view.drawableSize)
        }

        // Render wireframe if enabled and available
        if appState.showWireframe, let wireframeData = appState.wireframeData {
            renderWireframe(encoder: renderEncoder, wireframeData: wireframeData, appState: appState, viewSize: view.drawableSize)
        }

        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Mesh Rendering

    private func renderMesh(encoder: MTLRenderCommandEncoder, meshData: MeshData, appState: AppState, viewSize: CGSize) {
        encoder.setRenderPipelineState(meshPipelineState)
        encoder.setDepthStencilState(depthStencilState)

        // Set vertex buffer
        encoder.setVertexBuffer(meshData.vertexBuffer, offset: 0, index: 0)

        // Create uniforms
        let aspect = Float(viewSize.width / viewSize.height)
        var uniforms = createUniforms(camera: appState.camera, aspect: aspect)

        // Set uniforms
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)

        // Draw triangles
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: meshData.vertexCount)
    }

    private func renderGrid(encoder: MTLRenderCommandEncoder, gridData: GridData, appState: AppState, viewSize: CGSize) {
        encoder.setRenderPipelineState(gridPipelineState)
        encoder.setDepthStencilState(depthStencilState)

        // Set vertex buffer
        encoder.setVertexBuffer(gridData.vertexBuffer, offset: 0, index: 0)

        // Create and set uniforms
        let aspect = Float(viewSize.width / viewSize.height)
        var uniforms = createUniforms(camera: appState.camera, aspect: aspect, viewportHeight: Float(viewSize.height))
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)

        // Draw grid lines
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridData.vertexCount)
    }

    private func renderWireframe(encoder: MTLRenderCommandEncoder, wireframeData: WireframeData, appState: AppState, viewSize: CGSize) {
        encoder.setRenderPipelineState(wireframePipelineState)
        encoder.setDepthStencilState(depthStencilState)

        // Set vertex buffer (cylinder geometry)
        encoder.setVertexBuffer(wireframeData.cylinderVertexBuffer, offset: 0, index: 0)

        // Create and set uniforms with viewport height for pixel-perfect wireframe
        let aspect = Float(viewSize.width / viewSize.height)
        var uniforms = createUniforms(camera: appState.camera, aspect: aspect, viewportHeight: Float(viewSize.height))
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)

        // Set instance buffer (transformation matrices for each edge)
        encoder.setVertexBuffer(wireframeData.instanceBuffer, offset: 0, index: 2)

        // Draw instanced cylinders
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: wireframeData.indexCount,
            indexType: .uint16,
            indexBuffer: wireframeData.cylinderIndexBuffer,
            indexBufferOffset: 0,
            instanceCount: wireframeData.instanceCount
        )
    }

    private func createUniforms(camera: Camera, aspect: Float, viewportHeight: Float = 0) -> Uniforms {
        let modelMatrix = simd_float4x4(1.0) // Identity - model at origin
        let viewMatrix = camera.viewMatrix()
        let projectionMatrix = camera.projectionMatrix(aspect: aspect)

        // Normal matrix (inverse transpose of model-view)
        let modelView = viewMatrix * modelMatrix
        let normalMatrix = simd_float3x3(
            simd_float3(modelView[0].x, modelView[0].y, modelView[0].z),
            simd_float3(modelView[1].x, modelView[1].y, modelView[1].z),
            simd_float3(modelView[2].x, modelView[2].y, modelView[2].z)
        )

        return Uniforms(
            modelMatrix: modelMatrix,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            normalMatrix: normalMatrix,
            cameraPosition: camera.position,
            viewportHeight: viewportHeight
        )
    }
}

enum MetalError: Error {
    case commandQueueCreationFailed
    case pipelineCreationFailed
    case shaderLoadingFailed
}
