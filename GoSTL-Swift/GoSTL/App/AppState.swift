import SwiftUI
import Observation
import Metal

/// Grid display modes
enum GridMode: Int, CaseIterable {
    case off = 0
    case bottom = 1
    case allSides = 2
    case oneMM = 3

    var description: String {
        switch self {
        case .off: return "Grid: Off"
        case .bottom: return "Grid: Bottom"
        case .allSides: return "Grid: All Sides"
        case .oneMM: return "Grid: 1mm"
        }
    }
}

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

    /// GPU grid text data for labels
    var gridTextData: TextBillboardData?

    /// GPU measurement data for rendering measurements
    var measurementData: MeasurementRenderData?

    /// GPU slice plane data for visualizing slice boundaries
    var slicePlaneData: SlicePlaneData?

    /// GPU cut edge data for rendering sliced edges in axis colors
    var cutEdgeData: CutEdgeData?

    /// GPU orientation cube data for camera navigation
    var orientationCubeData: OrientationCubeData?

    /// Currently hovered face of the orientation cube (for hover effect)
    var hoveredCubeFace: CubeFace?

    /// Whether to show wireframe overlay
    var showWireframe: Bool = true

    /// Grid display mode
    var gridMode: GridMode = .bottom

    /// Whether to show model info overlay
    var showModelInfo: Bool = true

    /// Measurement system for distance/angle/radius measurements
    var measurementSystem = MeasurementSystem()

    /// Slicing system for clipping model along axes
    var slicingState = SlicingState()

    /// File watching state
    var fileWatcher: FileWatcher?
    var sourceFileURL: URL?
    var tempSTLFileURL: URL?
    var isOpenSCAD: Bool = false
    var needsReload: Bool = false
    var isLoading: Bool = false
    var loadError: Error?
    var loadErrorID: UUID?

    init() {
        setupNotifications()
    }

    /// Set up notification observers for menu commands
    private func setupNotifications() {
        // View menu notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ToggleWireframe"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showWireframe.toggle()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetGridMode"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let mode = notification.object as? GridMode, let self = self {
                self.gridMode = mode
                if let device = MTLCreateSystemDefaultDevice() {
                    try? self.updateGrid(device: device)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CycleGridMode"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let self = self {
                self.cycleGridMode()
                if let device = MTLCreateSystemDefaultDevice() {
                    try? self.updateGrid(device: device)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ToggleSlicing"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.slicingState.toggleVisibility()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetCameraPreset"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let preset = notification.object as? CameraPreset {
                self?.camera.setPreset(preset)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ResetCamera"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.camera.reset()
        }

        // Tools menu notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StartMeasurement"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let type = notification.object as? MeasurementType {
                self?.measurementSystem.startMeasurement(type: type)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ClearMeasurements"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.measurementSystem.clearAll()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CycleMaterial"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let self = self, var modelInfo = self.modelInfo {
                modelInfo.cycleMaterial()
                self.modelInfo = modelInfo
            }
        }
    }

    /// Cycle to the next grid mode
    func cycleGridMode() {
        let allModes = GridMode.allCases
        let currentIndex = allModes.firstIndex(of: gridMode) ?? 0
        let nextIndex = (currentIndex + 1) % allModes.count
        gridMode = allModes[nextIndex]
        print(gridMode.description)
    }

    /// Initialize grid
    func initializeGrid(device: MTLDevice) throws {
        self.gridData = try GridData(device: device, size: 100.0, spacing: 10.0)
    }

    /// Update grid based on current mode and model bounds
    func updateGrid(device: MTLDevice) throws {
        guard let model = model else { return }
        let bbox = model.boundingBox()
        self.gridData = try GridData(device: device, mode: gridMode, boundingBox: bbox)

        // Generate text labels for grid
        if let gridData = gridData, gridMode != .off {
            var allLabels = gridData.generateGridLabels()
            allLabels.append(contentsOf: gridData.generateDimensionLabels())
            if !allLabels.isEmpty {
                self.gridTextData = try TextBillboardData(device: device, labels: allLabels)
            } else {
                self.gridTextData = nil
            }
        } else {
            self.gridTextData = nil
        }
    }

    /// Initialize measurement rendering
    func initializeMeasurements(device: MTLDevice, thickness: Float = 0.01) {
        do {
            self.measurementData = try MeasurementRenderData(device: device, thickness: thickness)
        } catch {
            print("ERROR: Failed to create measurement data: \(error)")
        }
    }

    /// Initialize orientation cube
    func initializeOrientationCube(device: MTLDevice) {
        do {
            self.orientationCubeData = try OrientationCubeData(device: device, size: 1.0)
        } catch {
            print("ERROR: Failed to create orientation cube: \(error)")
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

        // Initialize grid based on model bounds
        try updateGrid(device: device)

        // Frame the model in view
        camera.frameBoundingBox(bbox)

        // Initialize slicing bounds
        slicingState.initializeBounds(from: bbox)

        // Clear all measurements when loading a new model
        measurementSystem.clearAll()

        // Clear loading state
        isLoading = false
    }

    /// Load a file from URL (supports both .stl and .scad files)
    func loadFile(_ url: URL, device: MTLDevice) throws {
        // Stop existing file watcher
        fileWatcher?.stop()
        fileWatcher = nil

        // Clean up old temp file if exists
        if let tempURL = tempSTLFileURL, isOpenSCAD {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let fileExtension = url.pathExtension.lowercased()

        if fileExtension == "scad" {
            // OpenSCAD file - render to temporary STL
            print("Rendering OpenSCAD file: \(url.lastPathComponent)")

            let workDir = url.deletingLastPathComponent()
            let renderer = OpenSCADRenderer(workDir: workDir)

            // Create temporary STL file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("gostl_temp_\(Int(Date().timeIntervalSince1970)).stl")

            // Render OpenSCAD to STL
            try renderer.renderToSTL(scadFile: url, outputFile: tempURL)
            print("Rendered to: \(tempURL.path)")

            // Parse the generated STL
            let model = try STLParser.parse(url: tempURL)
            try loadModel(model, device: device)

            // Update file watching state
            self.sourceFileURL = url
            self.tempSTLFileURL = tempURL
            self.isOpenSCAD = true
            self.modelInfo = ModelInfo(fileName: url.lastPathComponent, model: model)

            print("Successfully loaded: \(model.triangleCount) triangles")

        } else if fileExtension == "stl" {
            // Regular STL file
            print("Loading STL file: \(url.lastPathComponent)")
            let model = try STLParser.parse(url: url)
            try loadModel(model, device: device)

            // Update file watching state
            self.sourceFileURL = url
            self.tempSTLFileURL = nil
            self.isOpenSCAD = false
            self.modelInfo = ModelInfo(fileName: url.lastPathComponent, model: model)

            print("Successfully loaded: \(model.triangleCount) triangles")

        } else {
            throw FileLoadError.unsupportedFileType(fileExtension)
        }
    }

    /// Set up file watching for the currently loaded file
    func setupFileWatcher() throws {
        guard let sourceURL = sourceFileURL else {
            print("No source file to watch")
            return
        }

        let watcher = FileWatcher(debounceInterval: 0.5)
        var filesToWatch: [URL] = []

        if isOpenSCAD {
            // For OpenSCAD files, watch the source file and all dependencies
            let workDir = sourceURL.deletingLastPathComponent()
            let renderer = OpenSCADRenderer(workDir: workDir)

            let deps = try renderer.resolveDependencies(scadFile: sourceURL)
            filesToWatch = deps
        } else {
            // For STL files, just watch the source file
            filesToWatch = [sourceURL]
        }

        // Set up callback for file changes
        try watcher.watch(files: filesToWatch) { [weak self] changedFile in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.needsReload = true
            }
        }

        self.fileWatcher = watcher
    }

    /// Reload the model from the source file
    func reloadModel(device: MTLDevice) {
        guard let sourceURL = sourceFileURL else {
            print("No source file to reload")
            return
        }

        // If already loading, skip
        if isLoading {
            return
        }

        isLoading = true
        print("Reloading model...")

        // Perform loading in background
        Task.detached { [weak self] in
            guard let self = self else { return }

            do {
                var model: STLModel
                var tempURL: URL?

                if self.isOpenSCAD {
                    // Render OpenSCAD to STL
                    let workDir = sourceURL.deletingLastPathComponent()
                    let renderer = OpenSCADRenderer(workDir: workDir)

                    let newTempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("gostl_temp_\(Int(Date().timeIntervalSince1970)).stl")

                    try renderer.renderToSTL(scadFile: sourceURL, outputFile: newTempURL)
                    model = try STLParser.parse(url: newTempURL)
                    tempURL = newTempURL
                } else {
                    // Load STL directly
                    model = try STLParser.parse(url: sourceURL)
                }

                // Apply loaded model on main thread
                await MainActor.run {
                    do {
                        // Clean up old temp file if exists
                        if let oldTempURL = self.tempSTLFileURL, self.isOpenSCAD, oldTempURL != tempURL {
                            try? FileManager.default.removeItem(at: oldTempURL)
                        }

                        // Update temp file reference
                        if let tempURL = tempURL {
                            self.tempSTLFileURL = tempURL
                        }

                        // Load the new model
                        try self.loadModel(model, device: device)
                        self.modelInfo = ModelInfo(fileName: sourceURL.lastPathComponent, model: model)

                        print("Model reloaded successfully!")
                        self.isLoading = false
                        self.needsReload = false
                        self.loadError = nil
                        self.loadErrorID = nil
                    } catch {
                        print("ERROR: Failed to apply reloaded model: \(error)")
                        self.isLoading = false
                        self.needsReload = false  // Reset so next change can trigger reload
                        self.loadError = error
                        self.loadErrorID = UUID()
                    }
                }
            } catch {
                await MainActor.run {
                    print("ERROR: Failed to reload model: \(error)")
                    self.isLoading = false
                    self.needsReload = false  // Reset so next change can trigger reload
                    self.loadError = error
                    self.loadErrorID = UUID()
                }
            }
        }
    }

    /// Cycle to the next material type (for weight calculation)
    func cycleMaterial() {
        if var info = modelInfo {
            info.material = info.material.next()
            self.modelInfo = info
            print("Material changed to: \(info.material.rawValue)")
        }
    }
}

/// Errors that can occur during file loading
enum FileLoadError: LocalizedError {
    case unsupportedFileType(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "Unsupported file type: .\(ext) (expected .stl or .scad)"
        }
    }
}
