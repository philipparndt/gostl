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
    /// Notification observer tokens for cleanup (not observed by SwiftUI)
    @ObservationIgnored
    private var notificationObservers: [Any] = []

    /// Clear color for the background (dark blue matching Go version: RGB 15, 18, 25)
    var clearColor: SIMD4<Float> = SIMD4(0.059, 0.071, 0.098, 1.0)

    /// Camera for 3D navigation
    var camera = Camera()

    /// Currently loaded STL model
    var model: STLModel?

    /// Spatial acceleration structure for fast ray casting and vertex snapping
    var spatialAccelerator: SpatialAccelerator?

    /// Whether the spatial accelerator is currently being built
    var isBuildingAccelerator: Bool = false

    /// Whether the wireframe is currently being built
    var isBuildingWireframe: Bool = false

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

    /// GPU data for rendering selected/hovered triangles
    var selectedTrianglesData: SelectedTrianglesData?

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

    /// Leveling system for rotating model to align two points
    var levelingState = LevelingState()

    /// File watching state
    var fileWatcher: FileWatcher?
    var sourceFileURL: URL?
    var tempSTLFileURL: URL?
    var isOpenSCAD: Bool = false

    /// Track if the model has been modified (e.g., by leveling)
    var isModelModified: Bool = false

    /// URL where the model was last saved (may differ from sourceFileURL after "Save As")
    var savedFileURL: URL?
    var isGo3mf: Bool = false
    var reloadRequestId: Int = 0  // Incremented to trigger reload - onChange fires on any change
    var isLoading: Bool = false
    var loadError: Error?
    var loadErrorID: UUID?

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

    deinit {
        // Remove all notification observers
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()

        // Stop the file watcher
        fileWatcher?.stop()
        fileWatcher = nil
    }

    /// Set up notification observers for menu commands
    private func setupNotifications() {
        // View menu notifications
        notificationObservers.append(NotificationCenter.default.addObserver(
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
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
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
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ToggleInfoPanel"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showModelInfo.toggle()
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
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
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
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
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ToggleSlicing"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.slicingState.toggleVisibility()
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetCameraPreset"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let preset = notification.object as? CameraPreset {
                self?.camera.setPreset(preset)
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ResetCamera"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.camera.reset()
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ReloadModel"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadRequestId += 1
        })

        // Tools menu notifications
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StartMeasurement"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let type = notification.object as? MeasurementType {
                self?.measurementSystem.startMeasurement(type: type)
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ClearMeasurements"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.measurementSystem.clearAll()
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CopyMeasurementsAsOpenSCAD"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.copyMeasurementsAsOpenSCAD(closeMesh: false)
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CopyMeasurementsAsOpenSCADClosed"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.copyMeasurementsAsOpenSCAD(closeMesh: true)
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CycleMaterial"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let self = self, var modelInfo = self.modelInfo {
                modelInfo.cycleMaterial()
                self.modelInfo = modelInfo
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenWithGo3mf"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            openWithGo3mf(sourceFileURL: self?.sourceFileURL)
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
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
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
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
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
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
        })

        // Leveling notifications
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StartLeveling"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.levelingState.startLeveling()
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UndoLeveling"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let device = MTLCreateSystemDefaultDevice() {
                try? self?.undoLeveling(device: device)
            }
        })
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

        // Initialize selected triangles data
        self.selectedTrianglesData = SelectedTrianglesData(device: device)
    }

    /// Update selected triangles rendering data
    func updateSelectedTriangles() {
        selectedTrianglesData?.update(
            model: model,
            selectedIndices: measurementSystem.selectedTriangles,
            hoveredIndex: measurementSystem.hoveredTriangle
        )
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
        self.spatialAccelerator = nil
        self.isBuildingAccelerator = false
        self.isBuildingWireframe = false
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

    /// Reset state for loading a new file (different from current file)
    /// This clears all model-related state but preserves view settings like wireframe mode
    /// - Parameter preserveSettings: If true, preserve wireframe mode, grid mode, build plate, etc.
    func resetForNewFile(preserveSettings: Bool = false) {
        // Stop existing file watcher
        fileWatcher?.stop()
        fileWatcher = nil

        // Clean up old temp file if exists
        if let tempURL = tempSTLFileURL, (isOpenSCAD || isGo3mf) {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Clear model-related state
        model = nil
        spatialAccelerator = nil
        isBuildingAccelerator = false
        isBuildingWireframe = false
        cachedEdges = nil
        cachedFeatureEdges = nil
        cachedStyledEdges = nil
        unclippedWireframeData = nil

        // Clear GPU data
        meshData = nil
        wireframeData = nil
        slicePlaneData = nil
        cutEdgeData = nil
        gridData = nil
        gridTextData = nil
        selectedTrianglesData = nil

        // Clear file references
        sourceFileURL = nil
        tempSTLFileURL = nil
        isOpenSCAD = false
        isGo3mf = false
        savedFileURL = nil
        isModelModified = false

        // Clear 3MF plate data
        threeMFParseResult = nil
        selectedPlateId = nil

        // Clear model info
        modelInfo = nil
        isEmptyFile = false

        // Clear loading/error state
        isLoading = false
        loadError = nil
        loadErrorID = nil

        // Reset slicing state
        slicingState.fullReset()

        // Clear measurements
        measurementSystem.clearAll()

        // Reset leveling state
        levelingState.fullReset()

        // Optionally reset view settings
        if !preserveSettings {
            // Reset to default view settings for a fresh file
            // Keep these as they are - user preferences
        }
    }

    /// Load an STL model and create mesh data for rendering
    /// - Parameters:
    ///   - model: The STL model to load
    ///   - device: Metal device for GPU resources
    ///   - preserveCamera: If true, preserve current camera position (for reloads)
    func loadModel(_ model: STLModel, device: MTLDevice, preserveCamera: Bool = false) throws {
        let loadStart = CFAbsoluteTimeGetCurrent()

        self.model = model
        self.cachedEdges = nil  // Clear edge cache for new model
        self.cachedFeatureEdges = nil  // Clear feature edge cache for new model
        self.cachedStyledEdges = nil  // Clear styled edge cache for new model
        self.unclippedWireframeData = nil  // Clear cached wireframe for new model
        self.spatialAccelerator = nil  // Clear while rebuilding
        self.isBuildingAccelerator = true

        // Build spatial acceleration structure asynchronously for fast ray casting
        // This allows the model to render immediately while acceleration builds in background
        let triangles = model.triangles
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let accelerator = SpatialAccelerator(triangles: triangles)
            DispatchQueue.main.async {
                self?.spatialAccelerator = accelerator
                self?.isBuildingAccelerator = false
            }
        }

        // Calculate bounding box and thickness for wireframe
        var t0 = CFAbsoluteTimeGetCurrent()
        let bbox = model.boundingBox()
        print("  boundingBox: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")

        let modelSize = bbox.diagonal
        let thickness = Float(modelSize) * 0.002 // 0.2% of model size

        // Show mesh immediately without wireframe
        self.wireframeData = nil
        t0 = CFAbsoluteTimeGetCurrent()
        self.meshData = try MeshData(device: device, model: model)
        print("  MeshData: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
        print("  Total loadModel setup: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - loadStart) * 1000))ms")

        // Build wireframe asynchronously for large models
        if model.triangles.count > 10000 && wireframeMode != .off {
            isBuildingWireframe = true
            let triangles = model.triangles
            let currentWireframeMode = wireframeMode
            let currentEdgeAngleThreshold = edgeAngleThreshold
            let currentSlicingState = slicingState

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                // Extract edges in background
                let styledEdges: [StyledEdge]?
                let edges: [Edge]?

                if currentWireframeMode == .edge {
                    styledEdges = STLModel(triangles: triangles).extractStyledEdges(angleThreshold: currentEdgeAngleThreshold)
                    edges = nil
                } else {
                    edges = STLModel(triangles: triangles).extractEdges()
                    styledEdges = nil
                }

                DispatchQueue.main.async {
                    guard let self = self else { return }

                    // Cache the extracted edges
                    if let styledEdges = styledEdges {
                        self.cachedStyledEdges = styledEdges
                    }
                    if let edges = edges {
                        self.cachedEdges = edges
                    }

                    // Create wireframe data
                    do {
                        if currentWireframeMode == .edge, let styledEdges = styledEdges {
                            if currentSlicingState.isVisible {
                                self.wireframeData = try WireframeData(device: device, styledEdges: styledEdges, thickness: thickness, sliceBounds: currentSlicingState.bounds)
                            } else {
                                self.wireframeData = try WireframeData(device: device, styledEdges: styledEdges, thickness: thickness)
                            }
                        } else if let edges = edges {
                            if currentSlicingState.isVisible {
                                self.wireframeData = try WireframeData(device: device, edges: edges, thickness: thickness, sliceBounds: currentSlicingState.bounds)
                            } else {
                                self.wireframeData = try WireframeData(device: device, edges: edges, thickness: thickness)
                            }
                        }
                        self.unclippedWireframeData = self.wireframeData
                    } catch {
                        print("ERROR: Failed to create wireframe data: \(error)")
                    }

                    self.isBuildingWireframe = false
                }
            }
        } else {
            // For small models, build wireframe synchronously
            try updateWireframe(device: device)
        }

        // Reinitialize measurement data with appropriate thickness for this model
        t0 = CFAbsoluteTimeGetCurrent()
        initializeMeasurements(device: device, thickness: thickness)
        print("  initializeMeasurements: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")

        // Initialize grid based on model bounds
        t0 = CFAbsoluteTimeGetCurrent()
        try updateGrid(device: device)
        print("  updateGrid: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")

        // Update build plate if one is selected
        t0 = CFAbsoluteTimeGetCurrent()
        if buildPlate != .off {
            updateBuildPlate(device: device)
        }
        print("  updateBuildPlate: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")

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
    /// - Parameters:
    ///   - url: The file URL to load
    ///   - device: Metal device for GPU resources
    ///   - isSameFile: If true, preserve settings like material (for reloads)
    func loadFile(_ url: URL, device: MTLDevice, isSameFile: Bool = false) throws {
        // Check if this is the same file (for determining whether to preserve settings)
        let shouldPreserveSettings = isSameFile || (sourceFileURL == url)

        // Reset state for the new file (cleans up watchers, temp files, etc.)
        if !shouldPreserveSettings {
            resetForNewFile(preserveSettings: false)
        } else {
            // Just stop watcher and clean temp file, but preserve settings
            fileWatcher?.stop()
            fileWatcher = nil
            if let tempURL = tempSTLFileURL, (isOpenSCAD || isGo3mf), tempURL != url {
                try? FileManager.default.removeItem(at: tempURL)
            }
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
            var t0 = CFAbsoluteTimeGetCurrent()
            let model = try STLParser.parse(url: url)
            print("  STL parsing: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms (\(model.triangleCount) triangles)")
            t0 = CFAbsoluteTimeGetCurrent()
            try loadModel(model, device: device)
            print("  loadModel total: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")

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
            // go3mf YAML configuration file - use external go3mf tool to build 3MF
            print("Loading go3mf config: \(url.lastPathComponent)")

            let workDir = url.deletingLastPathComponent()
            let renderer = Go3mfToolRenderer(workDir: workDir)

            // Create temporary 3MF file
            let temp3MFURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("gostl_go3mf_\(Int(Date().timeIntervalSince1970)).3mf")

            try renderer.buildTo3MF(yamlFile: url, outputFile: temp3MFURL)

            // Load the generated 3MF file
            let parseResult = try ThreeMFParser.parseWithPlates(url: temp3MFURL)
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
            self.tempSTLFileURL = temp3MFURL  // Store temp 3MF for cleanup
            self.isOpenSCAD = false
            self.isGo3mf = true
            self.modelInfo = ModelInfo(fileName: url.lastPathComponent, model: model)

            print("Successfully loaded go3mf config: \(model.triangleCount) triangles (\(parseResult.plates.count) plates)")

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

        let watcher = FileWatcher()
        var filesToWatch: [URL] = []

        if isGo3mf {
            // For go3mf YAML files, just watch the source file
            // (go3mf tool handles dependency resolution internally)
            filesToWatch = [sourceURL]
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
                    // Build go3mf YAML config using external go3mf tool
                    let workDir = sourceURL.deletingLastPathComponent()
                    let renderer = Go3mfToolRenderer(workDir: workDir)

                    let newTempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("gostl_go3mf_\(Int(Date().timeIntervalSince1970)).3mf")

                    try renderer.buildTo3MF(yamlFile: sourceURL, outputFile: newTempURL)

                    // Load the generated 3MF file (supports plates)
                    let parseResult = try ThreeMFParser.parseWithPlates(url: newTempURL)

                    // Get model based on selected plate
                    if let plateId = self.selectedPlateId, parseResult.plates.count > 1 {
                        model = parseResult.model(forPlate: plateId)
                    } else {
                        model = parseResult.modelWithAllPlates()
                    }

                    tempURL = newTempURL

                    // Update parse result on main thread
                    await MainActor.run {
                        self.threeMFParseResult = parseResult
                    }
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
                        // Clean up old temp file if exists (for both OpenSCAD and go3mf)
                        if let oldTempURL = self.tempSTLFileURL, (self.isOpenSCAD || self.isGo3mf), oldTempURL != tempURL {
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

    // MARK: - Leveling Methods

    /// Apply leveling rotation to the model
    /// Rotates the model so that the two selected points become level on the chosen axis
    func applyLevelingRotation(device: MTLDevice) throws {
        guard let model = model,
              let point1 = levelingState.point1,
              let point2 = levelingState.point2,
              let axis = levelingState.selectedAxis else {
            print("Leveling: Missing model or points")
            return
        }

        // Store current triangles for undo
        levelingState.storeForUndo(model.triangles)

        // Calculate rotation
        let bbox = model.boundingBox()
        let (rotAxis, angle) = Rotation.calculateLevelingRotation(
            point1: point1,
            point2: point2,
            targetAxis: axis,
            center: bbox.center
        )

        // Skip if no rotation needed
        guard abs(angle) > 1e-10 else {
            print("Leveling: Points already level on \(LevelingState.axisName(for: axis)) axis")
            levelingState.reset()
            return
        }

        // Apply rotation to model
        var newModel = model
        Rotation.rotateModel(&newModel, axis: rotAxis, angle: angle, center: bbox.center)

        // Update model and regenerate GPU data
        self.model = newModel
        cachedEdges = nil
        cachedFeatureEdges = nil
        cachedStyledEdges = nil
        unclippedWireframeData = nil
        try updateMeshData(device: device)
        try updateWireframe(device: device)
        try updateGrid(device: device)

        // Update model info for the new model
        if let sourceURL = sourceFileURL {
            modelInfo = ModelInfo(fileName: sourceURL.lastPathComponent, model: newModel)
        }

        print("Leveling: Rotated \(angle * 180 / .pi)° around \(rotAxis) to level on \(LevelingState.axisName(for: axis)) axis")

        // Mark model as modified
        isModelModified = true

        // Reset leveling state but keep undo available
        levelingState.reset()
    }

    /// Undo the last leveling rotation
    func undoLeveling(device: MTLDevice) throws {
        guard let previousTriangles = levelingState.previousModelTriangles else {
            print("Leveling: Nothing to undo")
            return
        }

        // Restore previous model
        self.model = STLModel(triangles: previousTriangles, name: model?.name)

        // Clear caches and regenerate GPU data
        cachedEdges = nil
        cachedFeatureEdges = nil
        cachedStyledEdges = nil
        unclippedWireframeData = nil
        try updateMeshData(device: device)
        try updateWireframe(device: device)
        try updateGrid(device: device)

        // Update model info for the restored model
        if let model = model, let sourceURL = sourceFileURL {
            modelInfo = ModelInfo(fileName: sourceURL.lastPathComponent, model: model)
        }

        // Clear undo state
        levelingState.clearUndo()

        print("Leveling: Undo complete")
    }

    // MARK: - Save/Export Methods

    /// Check if the model can be saved (has been modified and has a model)
    var canSave: Bool {
        model != nil && isModelModified
    }

    /// Check if "Save" should use existing file (vs requiring "Save As")
    var hasSaveDestination: Bool {
        // Can save directly if we have a saved URL or if source is an STL file (not OpenSCAD/3MF)
        if savedFileURL != nil {
            return true
        }
        if let sourceURL = sourceFileURL, !isOpenSCAD && !isGo3mf {
            let ext = sourceURL.pathExtension.lowercased()
            return ext == "stl"
        }
        return false
    }

    /// Save the model to the current file (or prompt for Save As if no destination)
    func saveModel() throws {
        guard let model = model else {
            throw STLExportError.emptyModel
        }

        // Determine save destination
        let destinationURL: URL
        if let savedURL = savedFileURL {
            destinationURL = savedURL
        } else if let sourceURL = sourceFileURL, !isOpenSCAD && !isGo3mf {
            destinationURL = sourceURL
        } else {
            // No valid destination - caller should use saveModelAs instead
            throw STLExportError.writeFailure("No save destination. Use Save As.")
        }

        try STLExporter.exportBinary(model: model, to: destinationURL)
        savedFileURL = destinationURL
        isModelModified = false

        print("Saved model to: \(destinationURL.path)")
    }

    /// Save the model to a new file
    /// - Parameter url: The destination URL
    func saveModelAs(to url: URL) throws {
        guard let model = model else {
            throw STLExportError.emptyModel
        }

        try STLExporter.exportBinary(model: model, to: url)
        savedFileURL = url
        isModelModified = false

        // Update model info with new filename
        modelInfo = ModelInfo(fileName: url.lastPathComponent, model: model)

        print("Saved model as: \(url.path)")
    }

    /// Copy measurements or selected triangles as OpenSCAD code to clipboard
    /// - Parameter closeMesh: If true, detect open edges and add faces to close the mesh
    func copyMeasurementsAsOpenSCAD(closeMesh: Bool = false) {
        // If we have selected triangles, export those as polyhedron
        if !measurementSystem.selectedTriangles.isEmpty, let model = model {
            let code = OpenSCADGenerator.generate(from: model.triangles, indices: measurementSystem.selectedTriangles, closeMesh: closeMesh)
            OpenSCADGenerator.copyToClipboard(code)
            let modeStr = closeMesh ? " (closed solid)" : ""
            print("Copied \(measurementSystem.selectedTriangles.count) triangle(s) as OpenSCAD polyhedron\(modeStr) to clipboard")
            return
        }

        // Otherwise, use selected measurements if any, otherwise use all measurements
        let measurementsToConvert: [Measurement]
        if !measurementSystem.selectedMeasurements.isEmpty {
            measurementsToConvert = measurementSystem.selectedMeasurements
                .sorted()
                .compactMap { index in
                    index < measurementSystem.measurements.count ? measurementSystem.measurements[index] : nil
                }
        } else {
            measurementsToConvert = measurementSystem.measurements
        }

        guard !measurementsToConvert.isEmpty else {
            print("No measurements or triangles to convert to OpenSCAD")
            return
        }

        let code = OpenSCADGenerator.generate(from: measurementsToConvert)
        OpenSCADGenerator.copyToClipboard(code)
        print("Copied \(measurementsToConvert.count) measurement(s) as OpenSCAD to clipboard")
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
