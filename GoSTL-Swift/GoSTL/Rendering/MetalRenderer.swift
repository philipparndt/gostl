import Metal
import MetalKit
import CoreText
import CoreGraphics

final class MetalRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let meshPipelineState: MTLRenderPipelineState
    let wireframePipelineState: MTLRenderPipelineState
    let gridPipelineState: MTLRenderPipelineState
    let measurementPipelineState: MTLRenderPipelineState
    let cutEdgePipelineState: MTLRenderPipelineState
    let texturedPipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    let transparentDepthStencilState: MTLDepthStencilState
    let orientationCubeDepthStencilState: MTLDepthStencilState
    let samplerState: MTLSamplerState

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
        self.measurementPipelineState = try Self.createMeshPipeline(device: device) // Reuse mesh pipeline for measurements
        self.cutEdgePipelineState = try Self.createCutEdgePipeline(device: device)
        self.texturedPipelineState = try Self.createTexturedPipeline(device: device)

        // Create depth stencil states
        self.depthStencilState = Self.createDepthStencilState(device: device)
        self.transparentDepthStencilState = Self.createTransparentDepthStencilState(device: device)
        self.orientationCubeDepthStencilState = Self.createOrientationCubeDepthStencilState(device: device)

        // Create sampler state for texture sampling
        self.samplerState = Self.createSamplerState(device: device)

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
        pipelineDescriptor.rasterSampleCount = 4  // 4x MSAA for smooth edges

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
        pipelineDescriptor.rasterSampleCount = 4  // 4x MSAA for smooth edges

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
        pipelineDescriptor.rasterSampleCount = 4  // 4x MSAA for smooth edges

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

    private static func createCutEdgePipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
        let library = try loadShaderLibrary(device: device)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "cutEdgeVertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "cutEdgeFragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.rasterSampleCount = 4  // 4x MSAA for smooth edges

        // Same vertex descriptor as mesh/wireframe
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

    private static func createTexturedPipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
        let library = try loadShaderLibrary(device: device)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "texturedVertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "texturedFragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.rasterSampleCount = 4  // 4x MSAA for smooth edges

        // Enable alpha blending for text transparency
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add

        // Vertex descriptor with texCoord
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
        // TexCoord (attribute 3)
        vertexDescriptor.attributes[3].format = .float2
        vertexDescriptor.attributes[3].offset = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[3].bufferIndex = 0
        // Layout
        vertexDescriptor.layouts[0].stride = MemoryLayout<VertexIn>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    private static func createSamplerState(device: MTLDevice) -> MTLSamplerState {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: samplerDescriptor)!
    }

    private static func createDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: depthDescriptor)!
    }

    private static func createTransparentDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = false // Don't write depth for transparent objects
        return device.makeDepthStencilState(descriptor: depthDescriptor)!
    }

    private static func createOrientationCubeDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual // Use normal depth test
        depthDescriptor.isDepthWriteEnabled = true // Write depth so cube faces occlude each other
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
        if appState.gridMode != .off, let gridData = appState.gridData {
            renderGrid(encoder: renderEncoder, gridData: gridData, appState: appState, viewSize: view.drawableSize)
        }

        // Render slice planes (before mesh, for depth sorting)
        if let slicePlaneData = appState.slicePlaneData {
            renderSlicePlanes(encoder: renderEncoder, slicePlaneData: slicePlaneData, appState: appState, viewSize: view.drawableSize)
        }

        // Render mesh if available
        if let meshData = appState.meshData {
            renderMesh(encoder: renderEncoder, meshData: meshData, appState: appState, viewSize: view.drawableSize)
        }

        // Render wireframe if enabled and available
        if appState.showWireframe, let wireframeData = appState.wireframeData {
            renderWireframe(encoder: renderEncoder, wireframeData: wireframeData, appState: appState, viewSize: view.drawableSize)
        }

        // Render cut edges (from slicing)
        if let cutEdgeData = appState.cutEdgeData {
            renderCutEdges(encoder: renderEncoder, cutEdgeData: cutEdgeData, appState: appState, viewSize: view.drawableSize)
        }

        // Update and render measurements
        if let measurementData = appState.measurementData {
            measurementData.update(measurementSystem: appState.measurementSystem)
            renderMeasurements(encoder: renderEncoder, measurementData: measurementData, appState: appState, viewSize: view.drawableSize)
        }

        // Render grid text labels (3D text)
        if appState.gridMode != .off, let gridTextData = appState.gridTextData {
            renderTextBillboards(encoder: renderEncoder, textData: gridTextData, appState: appState, viewSize: view.drawableSize)
        }

        // Render orientation cube (top right corner)
        if let orientationCubeData = appState.orientationCubeData {
            renderOrientationCube(encoder: renderEncoder, cubeData: orientationCubeData, appState: appState, viewSize: view.drawableSize)
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

        // Get material from app state and create material properties
        let material = appState.modelInfo?.material ?? .pla
        var materialProperties = MaterialProperties(
            baseColor: material.baseColor,
            glossiness: material.glossiness,
            metalness: material.metalness,
            specularIntensity: material.specularIntensity
        )

        // Set material properties for fragment shader
        encoder.setFragmentBytes(&materialProperties, length: MemoryLayout<MaterialProperties>.size, index: 1)

        // Also pass uniforms to fragment shader for camera position
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 0)

        // Draw triangles
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: meshData.vertexCount)
    }

    private func renderGrid(encoder: MTLRenderCommandEncoder, gridData: GridData, appState: AppState, viewSize: CGSize) {
        encoder.setRenderPipelineState(gridPipelineState)
        encoder.setDepthStencilState(depthStencilState)

        // Create and set uniforms
        let aspect = Float(viewSize.width / viewSize.height)
        var uniforms = createUniforms(camera: appState.camera, aspect: aspect, viewportHeight: Float(viewSize.height))
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)

        // Draw grid lines
        encoder.setVertexBuffer(gridData.vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridData.vertexCount)

        // Draw dimension lines
        if let dimensionBuffer = gridData.dimensionLinesBuffer, gridData.dimensionLinesCount > 0 {
            encoder.setVertexBuffer(dimensionBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridData.dimensionLinesCount)
        }
    }

    private func renderSlicePlanes(encoder: MTLRenderCommandEncoder, slicePlaneData: SlicePlaneData, appState: AppState, viewSize: CGSize) {
        // Use grid pipeline for alpha blending support
        encoder.setRenderPipelineState(gridPipelineState)
        encoder.setDepthStencilState(depthStencilState)

        // Set vertex buffer
        encoder.setVertexBuffer(slicePlaneData.vertexBuffer, offset: 0, index: 0)

        // Create and set uniforms
        let aspect = Float(viewSize.width / viewSize.height)
        var uniforms = createUniforms(camera: appState.camera, aspect: aspect)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)

        // Draw slice planes
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: slicePlaneData.vertexCount)
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

    private func renderCutEdges(encoder: MTLRenderCommandEncoder, cutEdgeData: CutEdgeData, appState: AppState, viewSize: CGSize) {
        encoder.setRenderPipelineState(cutEdgePipelineState)
        encoder.setDepthStencilState(depthStencilState)

        // Set vertex buffer (cylinder geometry)
        encoder.setVertexBuffer(cutEdgeData.vertexBuffer, offset: 0, index: 0)

        // Create and set uniforms with viewport height for pixel-perfect thickness
        let aspect = Float(viewSize.width / viewSize.height)
        var uniforms = createUniforms(camera: appState.camera, aspect: aspect, viewportHeight: Float(viewSize.height))
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)

        // Set instance buffer (transformation matrices + colors for each edge)
        encoder.setVertexBuffer(cutEdgeData.instanceBuffer, offset: 0, index: 2)

        // Draw instanced cylinders
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: cutEdgeData.indexCount,
            indexType: .uint16,
            indexBuffer: cutEdgeData.indexBuffer,
            indexBufferOffset: 0,
            instanceCount: cutEdgeData.instanceCount
        )
    }

    private func renderMeasurements(encoder: MTLRenderCommandEncoder, measurementData: MeasurementRenderData, appState: AppState, viewSize: CGSize) {
        let aspect = Float(viewSize.width / viewSize.height)
        let uniforms = createUniforms(camera: appState.camera, aspect: aspect, viewportHeight: Float(viewSize.height))

        // Render measurement lines using instanced cylinders (like wireframe)
        if let lineInstanceBuffer = measurementData.lineInstanceBuffer, measurementData.lineInstanceCount > 0 {
            encoder.setRenderPipelineState(wireframePipelineState)
            encoder.setDepthStencilState(depthStencilState)

            encoder.setVertexBuffer(measurementData.cylinderVertexBuffer, offset: 0, index: 0)
            var uniformsCopy = uniforms
            encoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<Uniforms>.size, index: 1)
            encoder.setVertexBuffer(lineInstanceBuffer, offset: 0, index: 2)

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: measurementData.indexCount,
                indexType: .uint16,
                indexBuffer: measurementData.cylinderIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: measurementData.lineInstanceCount
            )
        }

        // Render preview line (bright green for normal, uses cylinder color for preview which is yellow for constrained)
        if let previewInstanceBuffer = measurementData.previewLineInstanceBuffer, measurementData.previewLineInstanceCount > 0 {
            encoder.setRenderPipelineState(wireframePipelineState)
            encoder.setDepthStencilState(depthStencilState)

            encoder.setVertexBuffer(measurementData.previewCylinderVertexBuffer, offset: 0, index: 0)
            var uniformsCopy = uniforms
            encoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<Uniforms>.size, index: 1)
            encoder.setVertexBuffer(previewInstanceBuffer, offset: 0, index: 2)

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: measurementData.indexCount,
                indexType: .uint16,
                indexBuffer: measurementData.cylinderIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: measurementData.previewLineInstanceCount
            )
        }

        // Render constraint line (red line from constrained endpoint to snap point)
        if let constraintInstanceBuffer = measurementData.constraintLineInstanceBuffer, measurementData.constraintLineInstanceCount > 0 {
            encoder.setRenderPipelineState(wireframePipelineState)
            encoder.setDepthStencilState(depthStencilState)

            encoder.setVertexBuffer(measurementData.constraintCylinderVertexBuffer, offset: 0, index: 0)
            var uniformsCopy = uniforms
            encoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<Uniforms>.size, index: 1)
            encoder.setVertexBuffer(constraintInstanceBuffer, offset: 0, index: 2)

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: measurementData.indexCount,
                indexType: .uint16,
                indexBuffer: measurementData.cylinderIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: measurementData.constraintLineInstanceCount
            )
        }

        // Render constrained endpoint marker (yellow cube at constrained position)
        if let constrainedPointBuffer = measurementData.constrainedPointBuffer, measurementData.constrainedPointVertexCount > 0 {
            encoder.setRenderPipelineState(measurementPipelineState)
            encoder.setDepthStencilState(depthStencilState)

            encoder.setVertexBuffer(constrainedPointBuffer, offset: 0, index: 0)
            var uniformsCopy = uniforms
            encoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: measurementData.constrainedPointVertexCount)
        }

        // Render measurement points
        if let pointBuffer = measurementData.pointBuffer, measurementData.pointCount > 0 {
            encoder.setRenderPipelineState(measurementPipelineState)
            encoder.setDepthStencilState(depthStencilState)

            encoder.setVertexBuffer(pointBuffer, offset: 0, index: 0)
            var uniformsCopy = uniforms
            encoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: measurementData.pointCount)
        }

        // Render hover point (on top, with slightly offset depth)
        if let hoverBuffer = measurementData.hoverBuffer, measurementData.hoverVertexCount > 0 {
            encoder.setRenderPipelineState(measurementPipelineState)
            encoder.setDepthStencilState(depthStencilState)

            encoder.setVertexBuffer(hoverBuffer, offset: 0, index: 0)
            var uniformsCopy = uniforms
            encoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: measurementData.hoverVertexCount)
        }

        // Render radius measurement circles (using instanced cylinders)
        if let circleInstanceBuffer = measurementData.radiusCircleInstanceBuffer, measurementData.radiusCircleInstanceCount > 0 {
            encoder.setRenderPipelineState(wireframePipelineState)
            encoder.setDepthStencilState(depthStencilState)

            encoder.setVertexBuffer(measurementData.radiusCircleCylinderVertexBuffer, offset: 0, index: 0)
            var uniformsCopy = uniforms
            encoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<Uniforms>.size, index: 1)
            encoder.setVertexBuffer(circleInstanceBuffer, offset: 0, index: 2)

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: measurementData.indexCount,
                indexType: .uint16,
                indexBuffer: measurementData.cylinderIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: measurementData.radiusCircleInstanceCount
            )
        }

        // Render radius measurement centers
        if let centerBuffer = measurementData.radiusCenterBuffer, measurementData.radiusCenterVertexCount > 0 {
            encoder.setRenderPipelineState(measurementPipelineState)
            encoder.setDepthStencilState(depthStencilState)

            encoder.setVertexBuffer(centerBuffer, offset: 0, index: 0)
            var uniformsCopy = uniforms
            encoder.setVertexBytes(&uniformsCopy, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: measurementData.radiusCenterVertexCount)
        }
    }

    private func renderTextBillboards(encoder: MTLRenderCommandEncoder, textData: TextBillboardData, appState: AppState, viewSize: CGSize) {
        encoder.setRenderPipelineState(texturedPipelineState)
        encoder.setDepthStencilState(transparentDepthStencilState) // Use transparent depth state to allow overlapping labels

        // Set vertex buffer
        encoder.setVertexBuffer(textData.vertexBuffer, offset: 0, index: 0)

        // Create and set uniforms
        let aspect = Float(viewSize.width / viewSize.height)
        var uniforms = createUniforms(camera: appState.camera, aspect: aspect)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)

        // Set sampler
        encoder.setFragmentSamplerState(samplerState, index: 0)

        // Render each text quad with its texture
        var vertexOffset = 0
        for textQuad in textData.textQuads {
            // Set texture for this quad
            encoder.setFragmentTexture(textQuad.texture, index: 0)

            // Draw the quad (6 vertices = 2 triangles)
            encoder.drawPrimitives(type: .triangle, vertexStart: vertexOffset, vertexCount: 6)
            vertexOffset += 6
        }
    }

    private func renderOrientationCube(encoder: MTLRenderCommandEncoder, cubeData: OrientationCubeData, appState: AppState, viewSize: CGSize) {
        // Define cube viewport in top-right corner
        // Note: Metal framebuffer coordinates have Y=0 at TOP, so originY=margin places
        // the viewport margin pixels from the top edge, resulting in top-right placement.
        let cubeSize: Double = 300  // Size of the cube viewport in pixels (2.5x larger: 120 * 2.5 = 300)
        let margin: Double = 20
        let viewport = MTLViewport(
            originX: viewSize.width - cubeSize - margin,
            originY: margin,  // Top-right corner (Metal framebuffer has Y=0 at TOP)
            width: cubeSize,
            height: cubeSize,
            znear: 0.0,
            zfar: 0.01  // Very shallow depth range ensures cube is always in front
        )

        encoder.setViewport(viewport)
        encoder.setRenderPipelineState(meshPipelineState)
        encoder.setDepthStencilState(orientationCubeDepthStencilState) // Always render on top

        // Create a camera that only rotates (doesn't translate) to show orientation
        let cubeCamera = Camera()
        cubeCamera.angleX = appState.camera.angleX
        cubeCamera.angleY = appState.camera.angleY
        cubeCamera.distance = 3.0  // Fixed distance for cube
        cubeCamera.target = SIMD3<Float>(0, 0, 0)  // Always look at origin

        // Create uniforms with cube camera
        let aspect = Float(cubeSize / cubeSize)  // Square viewport
        var uniforms = createUniforms(camera: cubeCamera, aspect: aspect)

        // Update vertex colors for hover effect if needed
        if let hoveredFace = appState.hoveredCubeFace {
            // Create modified vertex buffer with hover colors
            let vertices = createCubeVerticesWithHover(cubeData: cubeData, hoveredFace: hoveredFace)
            encoder.setVertexBytes(vertices, length: vertices.count * MemoryLayout<VertexIn>.stride, index: 0)
        } else {
            encoder.setVertexBuffer(cubeData.vertexBuffer, offset: 0, index: 0)
        }

        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)

        // Create default material properties for orientation cube (non-glossy, neutral)
        var materialProperties = MaterialProperties(
            baseColor: SIMD3<Float>(1.0, 1.0, 1.0),  // White (vertex colors will multiply)
            glossiness: 0.1,
            metalness: 0.0,
            specularIntensity: 0.2
        )
        encoder.setFragmentBytes(&materialProperties, length: MemoryLayout<MaterialProperties>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 0)

        // Draw cube
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cubeData.vertexCount)

        // Render 3D text labels on cube faces
        if let textBuffer = cubeData.textVertexBuffer, !cubeData.textTextures.isEmpty {
            encoder.setRenderPipelineState(texturedPipelineState)
            encoder.setVertexBuffer(textBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
            encoder.setFragmentSamplerState(samplerState, index: 0)

            // Render each text quad with its texture
            for (texture, vertexOffset) in cubeData.textTextures {
                encoder.setFragmentTexture(texture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: vertexOffset, vertexCount: 6)
            }
        }

        // Render axis lines (thick cylinders)
        if let axisVertexBuffer = cubeData.axisVertexBuffer,
           let axisIndexBuffer = cubeData.axisIndexBuffer,
           cubeData.axisIndexCount > 0 {
            encoder.setRenderPipelineState(meshPipelineState)
            encoder.setVertexBuffer(axisVertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: cubeData.axisIndexCount,
                indexType: .uint16,
                indexBuffer: axisIndexBuffer,
                indexBufferOffset: 0
            )
        }

        // Render axis labels as camera-facing billboards
        if !cubeData.axisLabels.isEmpty {
            encoder.setRenderPipelineState(texturedPipelineState)
            encoder.setFragmentSamplerState(samplerState, index: 0)

            let hoveredAxis = appState.measurementSystem.hoveredAxisLabel
            let constrainedAxis = appState.measurementSystem.constrainedAxis
            let hasConstraint = constrainedAxis >= 0

            // Generate billboard quads for each label based on current camera orientation
            for label in cubeData.axisLabels {
                let axisIndex = label.axis.rawValue
                let isHovered = axisIndex == hoveredAxis
                let isConstrained = axisIndex == constrainedAxis

                // Calculate size: larger when hovered
                let displaySize = isHovered ? label.size * 1.3 : label.size

                // Calculate alpha: dim non-constrained axes when constraint is active
                let alpha: Float
                if hasConstraint {
                    alpha = isConstrained ? 1.0 : 0.3
                } else {
                    alpha = isHovered ? 1.0 : 0.8
                }

                var billboardVertices = createBillboardQuad(
                    position: label.position,
                    size: displaySize,
                    camera: cubeCamera
                )

                // Apply alpha to vertex colors
                for i in 0..<billboardVertices.count {
                    billboardVertices[i].color.w = alpha
                }

                encoder.setVertexBytes(billboardVertices, length: billboardVertices.count * MemoryLayout<VertexIn>.stride, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                encoder.setFragmentTexture(label.texture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }

        // Render keyboard shortcut backgrounds (with rounded rectangle texture)
        if let shortcutBgBuffer = cubeData.shortcutBackgroundBuffer,
           let backgroundTexture = cubeData.shortcutBackgroundTexture,
           cubeData.shortcutBackgroundCount > 0 {
            encoder.setRenderPipelineState(texturedPipelineState)
            encoder.setVertexBuffer(shortcutBgBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
            encoder.setFragmentTexture(backgroundTexture, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cubeData.shortcutBackgroundCount)
        }

        // Render keyboard shortcut text
        if let shortcutTextBuffer = cubeData.shortcutTextVertexBuffer, !cubeData.shortcutTextTextures.isEmpty {
            encoder.setRenderPipelineState(texturedPipelineState)
            encoder.setVertexBuffer(shortcutTextBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
            encoder.setFragmentSamplerState(samplerState, index: 0)

            // Render each shortcut text quad with its texture
            for (texture, vertexOffset) in cubeData.shortcutTextTextures {
                encoder.setFragmentTexture(texture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: vertexOffset, vertexCount: 6)
            }
        }

        // Reset viewport to full screen
        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: viewSize.width,
            height: viewSize.height,
            znear: 0.0,
            zfar: 1.0
        ))
    }

    /// Create a camera-facing billboard quad
    private func createBillboardQuad(position: SIMD3<Float>, size: Float, camera: Camera) -> [VertexIn] {
        // Calculate camera's right and up vectors in world space
        let viewMatrix = camera.viewMatrix()

        // Extract right and up vectors from view matrix (inverse of view transform)
        // The view matrix transforms from world to view space, so we need the inverse
        // Right vector is the first column, up is the second column
        let right = simd_normalize(SIMD3<Float>(viewMatrix[0][0], viewMatrix[1][0], viewMatrix[2][0]))
        let up = simd_normalize(SIMD3<Float>(viewMatrix[0][1], viewMatrix[1][1], viewMatrix[2][1]))

        let halfSize = size / 2.0
        let color = SIMD4<Float>(1, 1, 1, 1)
        let normal = simd_normalize(camera.position - position)  // Face towards camera

        // Create quad vertices - bottom-left, bottom-right, top-right, top-left
        let v0 = position - right * halfSize - up * halfSize
        let v1 = position + right * halfSize - up * halfSize
        let v2 = position + right * halfSize + up * halfSize
        let v3 = position - right * halfSize + up * halfSize

        return [
            // Triangle 1
            VertexIn(position: v0, normal: normal, color: color, texCoord: SIMD2(0, 0)),
            VertexIn(position: v1, normal: normal, color: color, texCoord: SIMD2(1, 0)),
            VertexIn(position: v2, normal: normal, color: color, texCoord: SIMD2(1, 1)),
            // Triangle 2
            VertexIn(position: v0, normal: normal, color: color, texCoord: SIMD2(0, 0)),
            VertexIn(position: v2, normal: normal, color: color, texCoord: SIMD2(1, 1)),
            VertexIn(position: v3, normal: normal, color: color, texCoord: SIMD2(0, 1))
        ]
    }

    /// Create cube vertices with hover effect for a specific face
    private func createCubeVerticesWithHover(cubeData: OrientationCubeData, hoveredFace: CubeFace) -> [VertexIn] {
        var vertices: [VertexIn] = []

        // Regenerate all vertices with proper colors based on hover state
        let s: Float = 0.5  // Half size

        func addQuad(
            v0: SIMD3<Float>, v1: SIMD3<Float>,
            v2: SIMD3<Float>, v3: SIMD3<Float>,
            normal: SIMD3<Float>, face: CubeFace
        ) {
            let color = (face == hoveredFace) ? face.hoverColor : face.baseColor
            vertices.append(VertexIn(position: v0, normal: normal, color: color))
            vertices.append(VertexIn(position: v1, normal: normal, color: color))
            vertices.append(VertexIn(position: v2, normal: normal, color: color))
            vertices.append(VertexIn(position: v0, normal: normal, color: color))
            vertices.append(VertexIn(position: v2, normal: normal, color: color))
            vertices.append(VertexIn(position: v3, normal: normal, color: color))
        }

        // Generate all faces with appropriate colors
        addQuad(v0: SIMD3(-s, s, -s), v1: SIMD3(s, s, -s), v2: SIMD3(s, s, s), v3: SIMD3(-s, s, s),
                normal: CubeFace.top.normal, face: .top)
        addQuad(v0: SIMD3(-s, -s, s), v1: SIMD3(s, -s, s), v2: SIMD3(s, -s, -s), v3: SIMD3(-s, -s, -s),
                normal: CubeFace.bottom.normal, face: .bottom)
        addQuad(v0: SIMD3(-s, -s, s), v1: SIMD3(s, -s, s), v2: SIMD3(s, s, s), v3: SIMD3(-s, s, s),
                normal: CubeFace.front.normal, face: .front)
        addQuad(v0: SIMD3(s, -s, -s), v1: SIMD3(-s, -s, -s), v2: SIMD3(-s, s, -s), v3: SIMD3(s, s, -s),
                normal: CubeFace.back.normal, face: .back)
        addQuad(v0: SIMD3(-s, -s, -s), v1: SIMD3(-s, -s, s), v2: SIMD3(-s, s, s), v3: SIMD3(-s, s, -s),
                normal: CubeFace.left.normal, face: .left)
        addQuad(v0: SIMD3(s, -s, s), v1: SIMD3(s, -s, -s), v2: SIMD3(s, s, -s), v3: SIMD3(s, s, s),
                normal: CubeFace.right.normal, face: .right)

        return vertices
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
    case bufferCreationFailed
}
