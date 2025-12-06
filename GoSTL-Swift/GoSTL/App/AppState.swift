import SwiftUI
import Observation
import Metal

// MARK: - Focused Value for Menu Access

struct AppStateFocusedValueKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[AppStateFocusedValueKey.self] }
        set { self[AppStateFocusedValueKey.self] = newValue }
    }
}

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

/// Wireframe display modes
enum WireframeMode: Int, CaseIterable {
    case off = 0
    case all = 1
    case edge = 2

    var description: String {
        switch self {
        case .off: return "Wireframe: Off"
        case .all: return "Wireframe: All"
        case .edge: return "Wireframe: Edge"
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

    /// Cached edges for wireframe rendering (extracted once when model loads)
    private var cachedEdges: [Edge]?

    /// Cached feature edges for wireframe rendering (extracted once when model loads)
    private var cachedFeatureEdges: [Edge]?

    /// Cached styled edges for edge mode (all edges with styling based on angle)
    private var cachedStyledEdges: [StyledEdge]?

    /// Unclipped wireframe for immediate display during slicing
    private var unclippedWireframeData: WireframeData?

    /// Task for background wireframe clipping (cancelled when new update comes in)
    private var wireframeUpdateTask: Task<Void, Never>?

    /// Throttle state for mesh updates during slider movement
    private var lastMeshUpdateTime: CFAbsoluteTime = 0
    private var pendingMeshUpdate: DispatchWorkItem?

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

    /// GPU build plate data for printer reference
    var buildPlateData: BuildPlateData?

    /// Currently selected build plate
    var buildPlate: BuildPlate = .off

    /// Build plate orientation (bottom or back)
    var buildPlateOrientation: BuildPlateOrientation = .bottom

    /// Currently hovered face of the orientation cube (for hover effect)
    var hoveredCubeFace: CubeFace?

    /// Wireframe display mode
    var wireframeMode: WireframeMode = .edge

    /// Edge angle threshold in degrees (for edge wireframe mode)
    /// Edges where adjacent faces differ by more than this angle are shown
    var edgeAngleThreshold: Double = 30.0

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
    var isGo3mf: Bool = false
    var reloadRequestId: Int = 0  // Incremented to trigger reload - onChange fires on any change
    var isLoading: Bool = false
    var loadError: Error?
    var loadErrorID: UUID?
    private var lastReloadTime: Date?

    /// Whether the current file is empty (produces no geometry)
    var isEmptyFile: Bool = false

    /// 3MF plate support
    var threeMFParseResult: ThreeMFParseResult?
    var selectedPlateId: Int?

    /// Available plates for the current 3MF file
    var availablePlates: [ThreeMFPlate] {
        threeMFParseResult?.plates ?? []
    }

    /// Whether the current file has multiple plates to choose from
    var hasMultiplePlates: Bool {
        availablePlates.count > 1
    }

    init() {
        setupNotifications()
    }

    /// Set up notification observers for menu commands
    private func setupNotifications() {
        // View menu notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CycleWireframeMode"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let self = self {
                self.cycleWireframeMode()
                if let device = MTLCreateSystemDefaultDevice() {
                    try? self.updateWireframe(device: device)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetWireframeMode"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let mode = notification.object as? WireframeMode, let self = self {
                self.wireframeMode = mode
                if let device = MTLCreateSystemDefaultDevice() {
                    try? self.updateWireframe(device: device)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ToggleInfoPanel"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showModelInfo.toggle()
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

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenWithGo3mf"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            openWithGo3mf(sourceFileURL: self?.sourceFileURL)
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetBuildPlate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let plate = notification.object as? BuildPlate, let self = self {
                self.buildPlate = plate
                if let device = MTLCreateSystemDefaultDevice() {
                    self.updateBuildPlate(device: device)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CycleBuildPlate"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let self = self {
                self.buildPlate = self.buildPlate.next()
                if let device = MTLCreateSystemDefaultDevice() {
                    self.updateBuildPlate(device: device)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ToggleBuildPlateOrientation"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let self = self {
                self.buildPlateOrientation = self.buildPlateOrientation.next()
                if let device = MTLCreateSystemDefaultDevice() {
                    self.updateBuildPlate(device: device)
                }
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

    /// Cycle to the next wireframe mode
    func cycleWireframeMode() {
        let allModes = WireframeMode.allCases
        let currentIndex = allModes.firstIndex(of: wireframeMode) ?? 0
        let nextIndex = (currentIndex + 1) % allModes.count
        wireframeMode = allModes[nextIndex]
        print(wireframeMode.description)
    }

    /// Update wireframe based on current mode
    func updateWireframe(device: MTLDevice) throws {
        guard let model = model else {
            wireframeData = nil
            return
        }

        if wireframeMode == .off {
            wireframeData = nil
            unclippedWireframeData = nil
            return
        }

        // Calculate wireframe thickness based on model size
        let bbox = model.boundingBox()
        let modelSize = bbox.diagonal
        let thickness = Float(modelSize) * 0.002

        // Create wireframe data based on mode
        if wireframeMode == .edge {
            // Edge mode: show all edges with styling (feature edges full, soft edges thin/transparent)
            if cachedStyledEdges == nil {
                cachedStyledEdges = model.extractStyledEdges(angleThreshold: edgeAngleThreshold)
            }
            let styledEdges = cachedStyledEdges!

            if slicingState.isVisible {
                wireframeData = try WireframeData(device: device, styledEdges: styledEdges, thickness: thickness, sliceBounds: slicingState.bounds)
            } else {
                wireframeData = try WireframeData(device: device, styledEdges: styledEdges, thickness: thickness)
            }
        } else {
            // All mode: show all edges with full width/opacity
            if cachedEdges == nil {
                cachedEdges = model.extractEdges()
            }
            let edges = cachedEdges!

            if slicingState.isVisible {
                wireframeData = try WireframeData(device: device, edges: edges, thickness: thickness, sliceBounds: slicingState.bounds)
            } else {
                wireframeData = try WireframeData(device: device, edges: edges, thickness: thickness)
            }
        }
        unclippedWireframeData = wireframeData
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

    /// Update build plate visualization
    func updateBuildPlate(device: MTLDevice) {
        if buildPlate == .off {
            self.buildPlateData = nil
        } else {
            do {
                let bbox = model?.boundingBox()
                self.buildPlateData = try BuildPlateData(
                    device: device,
                    buildPlate: buildPlate,
                    orientation: buildPlateOrientation,
                    modelBoundingBox: bbox
                )
            } catch {
                print("ERROR: Failed to create build plate data: \(error)")
                self.buildPlateData = nil
            }
        }
    }

    /// Update mesh data based on current slicing bounds (throttled during rapid updates)
    /// When slicing is active, updates are throttled to ~30fps to keep UI responsive
    func updateMeshData(device: MTLDevice) throws {
        guard model != nil else { return }

        // Throttle updates during slicing to maintain responsive UI
        // Target: max 30 updates/sec during slider movement
        let throttleInterval: CFAbsoluteTime = 0.033 // ~30fps

        let now = CFAbsoluteTimeGetCurrent()
        let timeSinceLastUpdate = now - lastMeshUpdateTime

        if slicingState.isVisible && timeSinceLastUpdate < throttleInterval {
            // Schedule a trailing update to ensure final position is rendered
            pendingMeshUpdate?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                try? self.updateMeshDataCore(device: device)
            }
            pendingMeshUpdate = workItem
            let delay = throttleInterval - timeSinceLastUpdate
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            return
        }

        // Cancel any pending update since we're doing one now
        pendingMeshUpdate?.cancel()
        pendingMeshUpdate = nil
        lastMeshUpdateTime = now

        try updateMeshDataCore(device: device)
    }

    /// Core mesh update logic (called by throttled wrapper)
    private func updateMeshDataCore(device: MTLDevice) throws {
        guard let model else { return }

        lastMeshUpdateTime = CFAbsoluteTimeGetCurrent()

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

                // Handle wireframe based on mode
                if wireframeMode == .edge {
                    // Edge mode with styled edges
                    if cachedStyledEdges == nil {
                        cachedStyledEdges = model.extractStyledEdges(angleThreshold: edgeAngleThreshold)
                    }
                    let styledEdges = cachedStyledEdges!

                    // Immediately show unclipped wireframe (or keep current clipped one)
                    if unclippedWireframeData == nil {
                        unclippedWireframeData = try WireframeData(device: device, styledEdges: styledEdges, thickness: thickness)
                    }

                    // Use unclipped wireframe immediately for responsive UI
                    if wireframeData == nil {
                        wireframeData = unclippedWireframeData
                    }

                    // Schedule debounced async wireframe clipping
                    let bounds = slicingState.bounds
                    scheduleWireframeUpdate(device: device, styledEdges: styledEdges, thickness: thickness, bounds: bounds)
                } else if wireframeMode == .all {
                    // All mode with plain edges
                    if cachedEdges == nil {
                        cachedEdges = model.extractEdges()
                    }
                    let edges = cachedEdges!

                    // Immediately show unclipped wireframe (or keep current clipped one)
                    if unclippedWireframeData == nil {
                        unclippedWireframeData = try WireframeData(device: device, edges: edges, thickness: thickness)
                    }

                    // Use unclipped wireframe immediately for responsive UI
                    if wireframeData == nil {
                        wireframeData = unclippedWireframeData
                    }

                    // Schedule debounced async wireframe clipping
                    let bounds = slicingState.bounds
                    scheduleWireframeUpdate(device: device, edges: edges, thickness: thickness, bounds: bounds)
                } else {
                    self.wireframeData = nil
                    self.unclippedWireframeData = nil
                }
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
            if slicingState.showPlanes && slicingState.activePlane != nil {
                let planeSize = Float(bbox.diagonal * 1.5)
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
            // Show full model - no clipping needed, create wireframe directly
            self.meshData = try MeshData(device: device, model: model)

            // Handle wireframe based on mode
            if wireframeMode == .edge {
                // Edge mode with styled edges
                if cachedStyledEdges == nil {
                    cachedStyledEdges = model.extractStyledEdges(angleThreshold: edgeAngleThreshold)
                }
                let styledEdges = cachedStyledEdges!

                if unclippedWireframeData == nil {
                    unclippedWireframeData = try WireframeData(device: device, styledEdges: styledEdges, thickness: thickness)
                }
                self.wireframeData = unclippedWireframeData
            } else if wireframeMode == .all {
                // All mode with plain edges
                if cachedEdges == nil {
                    cachedEdges = model.extractEdges()
                }
                let edges = cachedEdges!

                if unclippedWireframeData == nil {
                    unclippedWireframeData = try WireframeData(device: device, edges: edges, thickness: thickness)
                }
                self.wireframeData = unclippedWireframeData
            } else {
                self.wireframeData = nil
                self.unclippedWireframeData = nil
            }

            self.slicePlaneData = nil
            self.cutEdgeData = nil
        }
    }

    /// Schedule a debounced wireframe update (runs in background after brief delay)
    private func scheduleWireframeUpdate(device: MTLDevice, edges: [Edge], thickness: Float, bounds: [[Double]]) {
        // Cancel any existing background task
        wireframeUpdateTask?.cancel()

        // Start background task with debounce built-in
        wireframeUpdateTask = Task { @MainActor [weak self] in
            // Short delay to debounce rapid updates
            try? await Task.sleep(for: .milliseconds(16))

            // Check if cancelled during sleep
            if Task.isCancelled { return }

            // Create clipped wireframe (runs on main actor but WireframeData does its heavy lifting in parallel internally)
            do {
                let clippedWireframe = try WireframeData(device: device, edges: edges, thickness: thickness, sliceBounds: bounds)

                // Check if cancelled
                if Task.isCancelled { return }

                // Update directly (we're already on main actor)
                self?.wireframeData = clippedWireframe
            } catch {
                print("ERROR: Background wireframe update failed: \(error)")
            }
        }
    }

    /// Schedule a debounced wireframe update for styled edges (runs in background after brief delay)
    private func scheduleWireframeUpdate(device: MTLDevice, styledEdges: [StyledEdge], thickness: Float, bounds: [[Double]]) {
        // Cancel any existing background task
        wireframeUpdateTask?.cancel()

        // Start background task with debounce built-in
        wireframeUpdateTask = Task { @MainActor [weak self] in
            // Short delay to debounce rapid updates
            try? await Task.sleep(for: .milliseconds(16))

            // Check if cancelled during sleep
            if Task.isCancelled { return }

            // Create clipped wireframe (runs on main actor but WireframeData does its heavy lifting in parallel internally)
            do {
                let clippedWireframe = try WireframeData(device: device, styledEdges: styledEdges, thickness: thickness, sliceBounds: bounds)

                // Check if cancelled
                if Task.isCancelled { return }

                // Update directly (we're already on main actor)
                self?.wireframeData = clippedWireframe
            } catch {
                print("ERROR: Background wireframe update failed: \(error)")
            }
        }
    }

    /// Clear the current model (for empty files)
    func clearModel() {
        self.model = nil
        self.cachedEdges = nil
        self.cachedFeatureEdges = nil
        self.cachedStyledEdges = nil
        self.meshData = nil
        self.wireframeData = nil
        self.slicePlaneData = nil
        self.cutEdgeData = nil
        self.gridData = nil
        self.gridTextData = nil
        self.measurementSystem.clearAll()
    }

    /// Load an STL model and create mesh data for rendering
    /// - Parameters:
    ///   - model: The STL model to load
    ///   - device: Metal device for GPU resources
    ///   - preserveCamera: If true, preserve current camera position (for reloads)
    func loadModel(_ model: STLModel, device: MTLDevice, preserveCamera: Bool = false) throws {
        self.model = model
        self.cachedEdges = nil  // Clear edge cache for new model
        self.cachedFeatureEdges = nil  // Clear feature edge cache for new model
        self.cachedStyledEdges = nil  // Clear styled edge cache for new model
        self.unclippedWireframeData = nil  // Clear cached wireframe for new model
        try updateMeshData(device: device)

        // Calculate wireframe based on current mode
        let bbox = model.boundingBox()
        let modelSize = bbox.diagonal
        let thickness = Float(modelSize) * 0.002 // 0.2% of model size
        try updateWireframe(device: device)

        // Reinitialize measurement data with appropriate thickness for this model
        initializeMeasurements(device: device, thickness: thickness)

        // Initialize grid based on model bounds
        try updateGrid(device: device)

        // Update build plate if one is selected
        if buildPlate != .off {
            updateBuildPlate(device: device)
        }

        // Frame the model in view (only for initial load, not reloads)
        if !preserveCamera {
            camera.frameBoundingBox(bbox)
        }

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

            do {
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
                self.isGo3mf = false
                self.isEmptyFile = false
                self.threeMFParseResult = nil
                self.selectedPlateId = nil
                self.modelInfo = ModelInfo(fileName: url.lastPathComponent, model: model)

                print("Successfully loaded: \(model.triangleCount) triangles")
            } catch OpenSCADError.emptyFile {
                // Empty file - show blank view with info
                print("OpenSCAD file is empty: \(url.lastPathComponent)")
                clearModel()
                self.sourceFileURL = url
                self.tempSTLFileURL = nil
                self.isOpenSCAD = true
                self.isGo3mf = false
                self.isEmptyFile = true
                self.threeMFParseResult = nil
                self.selectedPlateId = nil
                self.modelInfo = ModelInfo(fileName: url.lastPathComponent, triangleCount: 0, volume: 0, boundingBox: BoundingBox())
                self.isLoading = false
                return
            }

        } else if fileExtension == "stl" {
            // Regular STL file
            print("Loading STL file: \(url.lastPathComponent)")
            let model = try STLParser.parse(url: url)
            try loadModel(model, device: device)

            // Update file watching state
            self.sourceFileURL = url
            self.tempSTLFileURL = nil
            self.isOpenSCAD = false
            self.isGo3mf = false
            self.threeMFParseResult = nil
            self.selectedPlateId = nil
            self.modelInfo = ModelInfo(fileName: url.lastPathComponent, model: model)

            print("Successfully loaded: \(model.triangleCount) triangles")

        } else if fileExtension == "3mf" {
            // 3MF file (3D Manufacturing Format)
            print("Loading 3MF file: \(url.lastPathComponent)")
            let parseResult = try ThreeMFParser.parseWithPlates(url: url)
            self.threeMFParseResult = parseResult

            // Select first plate by default, or show all if only one plate
            let initialPlateId = parseResult.plates.first?.id
            self.selectedPlateId = initialPlateId

            let model: STLModel
            if let plateId = initialPlateId, parseResult.plates.count > 1 {
                model = parseResult.model(forPlate: plateId)
                print("Loaded plate \(plateId): \(parseResult.plates.first { $0.id == plateId }?.name ?? "Unknown")")
            } else {
                model = parseResult.modelWithAllPlates()
            }

            try loadModel(model, device: device)

            // Update file watching state
            self.sourceFileURL = url
            self.tempSTLFileURL = nil
            self.isOpenSCAD = false
            self.isGo3mf = false
            self.modelInfo = ModelInfo(fileName: url.lastPathComponent, model: model)

            print("Successfully loaded: \(model.triangleCount) triangles (\(parseResult.plates.count) plates)")

        } else if fileExtension == "yaml" || fileExtension == "yml" {
            // go3mf YAML configuration file
            print("Loading go3mf config: \(url.lastPathComponent)")

            let renderer = try Go3mfRenderer(configURL: url)
            let model = try renderer.render()
            try loadModel(model, device: device)

            // Update file watching state
            self.sourceFileURL = url
            self.tempSTLFileURL = nil
            self.isOpenSCAD = false
            self.isGo3mf = true
            self.threeMFParseResult = nil
            self.selectedPlateId = nil
            self.modelInfo = ModelInfo(fileName: url.lastPathComponent, model: model)

            print("Successfully loaded go3mf config: \(model.triangleCount) triangles")

        } else {
            throw FileLoadError.unsupportedFileType(fileExtension)
        }
    }

    /// Select a different plate from a 3MF file
    func selectPlate(_ plateId: Int, device: MTLDevice) throws {
        guard let parseResult = threeMFParseResult else {
            print("No 3MF parse result available")
            return
        }

        guard parseResult.plates.contains(where: { $0.id == plateId }) else {
            print("Invalid plate ID: \(plateId)")
            return
        }

        self.selectedPlateId = plateId
        let model = parseResult.model(forPlate: plateId)

        // Clear cached data for the new model
        cachedEdges = nil
        cachedFeatureEdges = nil
        cachedStyledEdges = nil
        unclippedWireframeData = nil
        wireframeData = nil
        gridData = nil
        gridTextData = nil

        try loadModel(model, device: device, preserveCamera: false)

        // Update model info
        if let sourceURL = sourceFileURL {
            self.modelInfo = ModelInfo(fileName: sourceURL.lastPathComponent, model: model)
        }

        let plateName = parseResult.plates.first { $0.id == plateId }?.name ?? "Unknown"
        print("Switched to plate \(plateId): \(plateName) (\(model.triangleCount) triangles)")
    }

    /// Set up file watching for the currently loaded file
    func setupFileWatcher() throws {
        guard let sourceURL = sourceFileURL else {
            print("No source file to watch")
            return
        }

        let watcher = FileWatcher(debounceInterval: 1.0)
        var filesToWatch: [URL] = []

        if isGo3mf {
            // For go3mf YAML files, watch the config and all referenced files
            let renderer = try Go3mfRenderer(configURL: sourceURL)
            filesToWatch = renderer.getDependencies()
        } else if isOpenSCAD {
            // For OpenSCAD files, watch the source file and all dependencies
            let workDir = sourceURL.deletingLastPathComponent()
            let renderer = OpenSCADRenderer(workDir: workDir)

            let deps = try renderer.resolveDependencies(scadFile: sourceURL)
            filesToWatch = deps
        } else {
            // For STL/3MF files, just watch the source file
            filesToWatch = [sourceURL]
        }

        // Set up callback for file changes
        try watcher.watch(files: filesToWatch) { [weak self] changedFile in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.reloadRequestId += 1
                print("FileWatcher callback: reloadRequestId = \(self.reloadRequestId)")
            }
        }

        self.fileWatcher = watcher
    }

    /// Reload the model from the source file
    func reloadModel(device: MTLDevice) {
        print("reloadModel called - isLoading: \(isLoading), isPaused: \(fileWatcher?.isPaused ?? false)")

        guard let sourceURL = sourceFileURL else {
            print("No source file to reload")
            return
        }

        // If already loading, skip - the file watcher will trigger again if needed
        if isLoading {
            print("Reload requested but already loading - skipping")
            return
        }

        // Cooldown period after last reload to prevent rapid re-triggers
        if let lastReload = lastReloadTime, Date().timeIntervalSince(lastReload) < 1.0 {
            let remainingCooldown = 1.0 - Date().timeIntervalSince(lastReload)
            print("Reload delayed - cooldown period (\(String(format: "%.1f", remainingCooldown))s remaining)")
            // Schedule a retry after remaining cooldown
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingCooldown + 0.1) { [weak self] in
                guard let self = self else { return }
                print("Cooldown expired, triggering reload...")
                self.reloadRequestId += 1  // This will trigger the onChange observer
            }
            return
        }

        isLoading = true

        // Pause file watcher during reload to prevent re-triggers from generated files
        fileWatcher?.isPaused = true
        print("Reloading model from: \(sourceURL.lastPathComponent)")

        // Perform loading in background
        Task.detached { [weak self] in
            guard let self = self else { return }

            do {
                var model: STLModel
                var tempURL: URL?

                if self.isGo3mf {
                    // Render go3mf YAML config
                    let renderer = try Go3mfRenderer(configURL: sourceURL)
                    model = try renderer.render()
                } else if self.isOpenSCAD {
                    // Render OpenSCAD to STL
                    let workDir = sourceURL.deletingLastPathComponent()
                    let renderer = OpenSCADRenderer(workDir: workDir)

                    let newTempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("gostl_temp_\(Int(Date().timeIntervalSince1970)).stl")

                    try renderer.renderToSTL(scadFile: sourceURL, outputFile: newTempURL)
                    model = try STLParser.parse(url: newTempURL)
                    tempURL = newTempURL
                } else {
                    // Load STL/3MF directly
                    let ext = sourceURL.pathExtension.lowercased()
                    if ext == "3mf" {
                        model = try ThreeMFParser.parse(url: sourceURL)
                    } else {
                        model = try STLParser.parse(url: sourceURL)
                    }
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

                        // Load the new model, preserving camera position
                        try self.loadModel(model, device: device, preserveCamera: true)

                        // Preserve the selected material from previous model info
                        let previousMaterial = self.modelInfo?.material ?? .pla
                        var newModelInfo = ModelInfo(fileName: sourceURL.lastPathComponent, model: model)
                        newModelInfo.material = previousMaterial
                        self.modelInfo = newModelInfo
                        self.isEmptyFile = false

                        print("Model reloaded successfully!")
                        self.isLoading = false
                        self.loadError = nil
                        self.loadErrorID = nil
                        self.lastReloadTime = Date()

                        // Resume file watcher
                        self.fileWatcher?.isPaused = false
                    } catch {
                        print("ERROR: Failed to apply reloaded model: \(error)")
                        self.isLoading = false
                        self.loadError = error
                        self.loadErrorID = UUID()

                        // Resume file watcher
                        self.fileWatcher?.isPaused = false
                    }
                }
            } catch OpenSCADError.emptyFile {
                await MainActor.run {
                    print("OpenSCAD file is empty: \(sourceURL.lastPathComponent)")
                    self.clearModel()
                    self.isEmptyFile = true
                    self.modelInfo = ModelInfo(fileName: sourceURL.lastPathComponent)
                    self.isLoading = false
                    self.loadError = nil
                    self.loadErrorID = nil

                    // Resume file watcher
                    self.fileWatcher?.isPaused = false
                }
            } catch {
                await MainActor.run {
                    print("ERROR: Failed to reload model: \(error)")
                    self.isLoading = false
                    self.loadError = error
                    self.loadErrorID = UUID()

                    // Resume file watcher
                    self.fileWatcher?.isPaused = false
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
            return "Unsupported file type: .\(ext) (expected .stl, .3mf, .scad, or .yaml)"
        }
    }
}
