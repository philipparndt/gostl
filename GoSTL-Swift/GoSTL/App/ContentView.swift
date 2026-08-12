import SwiftUI
import Metal
import AppKit

public struct ContentView: View {
    @State private var appState = AppState()
    @State private var themePreferences = ThemePreferences.shared
    @State private var errorAlert: ErrorAlert?
    @State private var overlayError: ToolError?
    @State private var windowTitle: String = "GoSTL"
    @State private var windowNumber: Int = 0
    @State private var hasInitialized = false
    @State private var notificationObserver: NSObjectProtocol?
    @State private var go3mfErrorObserver: NSObjectProtocol?

    let fileURL: URL?
    let embedding: EmbeddingOptions?

    /// How the viewer should behave inside someone else's window.
    ///
    /// The defaults suit a window of its own; an editor showing a model in a
    /// split pane wants something quieter and in its own colours.
    public struct EmbeddingOptions: Sendable {
        /// Background for the viewport, so the pane matches its surroundings.
        public var backgroundColor: NSColor?
        /// Whether the menu panel is open to begin with. It covers most of a
        /// narrow pane, so an embedder usually wants it folded away behind its
        /// button until asked for.
        public var showsMenuPanel: Bool
        /// A way to render the current scene into an image, for an embedder
        /// whose screenshots cannot see Metal. Main-actor because the scene
        /// is: it reads the camera and the model as the view does.
        public typealias SnapshotProvider = @MainActor (CGSize) -> CGImage?

        /// Handed a way to photograph what the viewer is showing, once there
        /// is something to photograph.
        ///
        /// AppKit captures a window by walking its view tree, and a Metal
        /// layer's contents are not in it — so an embedder's screenshot has
        /// the model missing and nothing to say about why. Given this, it can
        /// ask for the frame and draw it where the pane is.
        public var snapshotHandle: (@MainActor (@escaping SnapshotProvider) -> Void)?

        /// How to run OpenSCAD, for an embedder that has an answer of its own.
        ///
        /// Nil means the copy installed on this machine, which is what the
        /// viewer has always used and what it uses when nothing is embedding it
        /// at all. An editor that runs its tools from container images can put
        /// one here instead, and then a `.scad` previews on a machine with no
        /// OpenSCAD installed — which is the one place a user actually feels
        /// this, because either the model appears or an overlay tells them to
        /// go and install a 200 MB cask.
        ///
        /// Whatever is supplied has to honour the working directory it is given
        /// on each call rather than fixing one: relative `include <…>` and
        /// `use <…>` resolve against it, and the renderer deliberately uses a
        /// different one for different passes.
        public var openSCAD: OpenSCADCommand?

        public init(
            backgroundColor: NSColor? = nil,
            showsMenuPanel: Bool = false,
            snapshotHandle: (@MainActor (@escaping SnapshotProvider) -> Void)? = nil,
            openSCAD: OpenSCADCommand? = nil
        ) {
            self.backgroundColor = backgroundColor
            self.showsMenuPanel = showsMenuPanel
            self.snapshotHandle = snapshotHandle
            self.openSCAD = openSCAD
        }
    }

    public init(fileURL: URL? = nil, embedding: EmbeddingOptions? = nil) {
        self.fileURL = fileURL
        self.embedding = embedding
    }

    /// The Metal viewport, built outside `body`.
    ///
    /// Inside it, the type checker gives up on the surrounding expression —
    /// which is already large — the moment this takes a second argument.
    private var viewport: MetalView {
        MetalView(appState: appState, snapshotHandle: embedding?.snapshotHandle)
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                viewport
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .onAppear {
                        print("DEBUG: MetalView appeared, geometry: \(geometry.size)")
                    }

                // Measurement labels (in 3D space)
                MeasurementLabelsOverlay(
                    measurementSystem: appState.measurementSystem,
                    camera: appState.camera,
                    viewSize: geometry.size
                )

                // Selection rectangle overlay
                SelectionRectangleOverlay(measurementSystem: appState.measurementSystem)

                // Floating overlay panels — kept in dark color scheme regardless of
                // the app theme so the .ultraThinMaterial glass stays dark enough
                // for the white text inside to remain readable in light mode.
                ZStack {
                    // Main menu panel (top-left), or the button that brings it
                    // back. Without the button the panel is reachable only by
                    // the "i" shortcut or a menu command, and an embedded
                    // viewer has neither.
                    VStack {
                        HStack {
                            if appState.showModelInfo {
                                MainMenuPanel(appState: appState, availableWidth: geometry.size.width)
                            } else {
                                MenuPanelButton { appState.showModelInfo = true }
                                    .padding(12)
                            }
                            Spacer()
                        }
                        Spacer()
                    }

                    // Slicing panel (bottom-right)
                    if appState.slicingState.isVisible {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                SlicingPanel(slicingState: appState.slicingState)
                                    .padding(12)
                            }
                        }
                    }

                    // Leveling panel (bottom-right, replaces slicing when active)
                    if appState.levelingState.isActive {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                LevelingPanel(
                                    levelingState: appState.levelingState,
                                    onApply: { axis in
                                        appState.levelingState.selectAxis(axis)
                                        applyLeveling()
                                    },
                                    onCancel: {
                                        appState.levelingState.reset()
                                    },
                                    onUndo: {
                                        guard let device = MTLCreateSystemDefaultDevice() else { return }
                                        try? appState.undoLeveling(device: device)
                                    }
                                )
                                .padding(12)
                            }
                        }
                    }

                    // Plate selector (bottom-center) - only shown for 3MF files with multiple plates
                    if appState.hasMultiplePlates {
                        VStack {
                            Spacer()
                            PlateSelector(appState: appState)
                                .padding(.bottom, 16)
                        }
                    }

                    // Warnings panel (bottom-right) - only shown when there are warnings
                    if !appState.renderWarnings.isEmpty && !appState.slicingState.isVisible && !appState.levelingState.isActive {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                WarningsPanel(warnings: appState.renderWarnings)
                                    .padding(12)
                            }
                        }
                    }

                    // Loading overlay (shown while waiting for file to load)
                    if appState.isLoading {
                        LoadingOverlay()
                            .transition(.opacity)
                    }

                    // Background processing indicator (shown while spatial index or wireframe builds)
                    if (appState.isBuildingAccelerator || appState.isBuildingWireframe) && !appState.isLoading {
                        VStack {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                                VStack(alignment: .leading, spacing: 2) {
                                    if appState.isBuildingWireframe {
                                        Text("Building wireframe...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if appState.isBuildingAccelerator {
                                        Text("Building spatial index...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 50)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(.easeInOut(duration: 0.3), value: appState.isBuildingAccelerator || appState.isBuildingWireframe)
                    }

                    // Empty file indicator (shown when OpenSCAD file has no geometry)
                    if appState.isEmptyFile {
                        EmptyFileOverlay(fileName: appState.modelInfo?.fileName ?? "")
                    }

                    // Error overlay (shown for tool errors)
                    if let error = overlayError {
                        ErrorOverlay(error: error) {
                            overlayError = nil
                            appState.loadError = nil
                            appState.loadErrorID = nil
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .environment(\.colorScheme, .dark)
            }
        }
        // A window of its own deserves a sensible minimum size. A pane in
        // someone else's window does not get to insist on one: the view would
        // stay 800pt wide inside a narrower pane, be clipped to what fits, and
        // everything anchored to its right edge — the orientation cube above
        // all — would sit outside what can be seen. The 3D view would also be
        // fitted to a viewport wider than the visible one, so the model came
        // out oversized and cut off.
        .frame(
            minWidth: embedding == nil ? 800 : nil,
            minHeight: embedding == nil ? 600 : nil
        )
        .navigationTitle(windowTitle)
        .focusedSceneValue(\.appState, appState)
        .preferredColorScheme(themePreferences.current.colorScheme)
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true

            if let embedding {
                appState.showModelInfo = embedding.showsMenuPanel
                if let color = embedding.backgroundColor {
                    appState.backgroundOverride = color.viewportComponents
                }
                // Before anything is loaded, which is what makes this the right
                // place: the file is opened further down this same block, and a
                // command handed over after that would arrive for the second
                // render rather than the first.
                if let openSCAD = embedding.openSCAD {
                    appState.openSCAD = openSCAD
                }
            }

            print("DEBUG: ContentView.onAppear, fileURL=\(fileURL?.lastPathComponent ?? "nil")")

            // Initialize rendering components
            if let device = MTLCreateSystemDefaultDevice() {
                do {
                    try appState.initializeGrid(device: device)
                    appState.initializeMeasurements(device: device)
                    appState.initializeOrientationCube(device: device)
                    print("DEBUG: Rendering initialized")
                } catch {
                    print("ERROR: Failed to initialize rendering: \(error)")
                }
            }

            // If file was passed directly (command line or new window), load it immediately
            if let url = fileURL {
                print("DEBUG: Loading from fileURL parameter: \(url.lastPathComponent)")
                windowTitle = url.lastPathComponent
                loadFileOnStartup(url)
                // Capture window number and set up notifications after a brief delay
                // to ensure the window is fully initialized
                DispatchQueue.main.async {
                    self.captureWindowAndSetupNotifications()
                }
                return
            }

            // Otherwise, wait for Finder files or show test cube
            Task { @MainActor in
                if let pendingFile = await FileOpenCoordinator.shared.claimInitialFile() {
                    print("DEBUG: Got file from coordinator: \(pendingFile.lastPathComponent)")
                    windowTitle = pendingFile.lastPathComponent
                    loadFileOnStartup(pendingFile)
                } else {
                    print("DEBUG: No pending files, showing test cube")
                    setupInitialState(loadTestCube: true)
                }
                // Capture window number and set up notifications
                self.captureWindowAndSetupNotifications()
            }
        }
        .onDisappear {
            // Clean up notification observers
            if let observer = notificationObserver {
                NotificationCenter.default.removeObserver(observer)
                notificationObserver = nil
            }
            if let observer = go3mfErrorObserver {
                NotificationCenter.default.removeObserver(observer)
                go3mfErrorObserver = nil
            }
        }
        .onChange(of: appState.slicingState.bounds) { _, _ in
            updateSlicedMesh()
        }
        .onChange(of: appState.slicingState.isVisible) { _, _ in
            updateSlicedMesh()
        }
        .onChange(of: appState.slicingState.showPlanes) { _, newValue in
            // Only update mesh if planes are being turned on (need to create slice plane data)
            // Turning off doesn't require mesh update
            if newValue {
                updateSlicedMesh()
            } else {
                // Just clear slice plane data without full mesh update
                appState.slicePlaneData = nil
            }
        }
        .onChange(of: appState.slicingState.activePlane != nil) { _, _ in
            // Only update slice plane visualization, not the whole mesh
            updateSlicePlaneOnly()
        }
        .onChange(of: appState.reloadRequestId) { _, _ in
            reloadModel()
        }
        // The overlay follows the load error, in both directions.
        //
        // Reading a cleared error as "a load succeeded" is an inference, and
        // 0484 reported it going wrong: the failure path set the overlay and
        // then loaded a test cube, whose load cleared the error and dismissed
        // the message one line after it was shown. Driving this version, the
        // overlay in fact survived - loading a model does not touch `loadError`,
        // and at startup `loadErrorID` was still nil so this never fired - so
        // what was seen was a cube *and* a message rather than a cube alone.
        // The reported mechanism is real all the same, and needs only a prior
        // error for a fallback's clearing to dismiss the message about the
        // failure it is falling back from.
        //
        // What makes the inference sound rather than lucky is that every place
        // which clears this is a load that worked: `reloadModel` on success, an
        // OpenSCAD file that rendered to no geometry, and `resetForNewFile` when
        // a different file is opened, which should indeed take the old message
        // away. A failure sets it and leaves it set (AppState.showFailedLoad),
        // and there is no longer a fallback load behind it.
        .onChange(of: appState.loadErrorID) { _, errorID in
            if let error = appState.loadError {
                handleLoadError(error, isAutoReload: true)
            } else if errorID == nil {
                // Error was cleared (successful reload), dismiss overlay
                withAnimation(.easeInOut(duration: 0.3)) {
                    overlayError = nil
                }
            }
        }
        .alert(item: $errorAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func updateSlicedMesh() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        do {
            try appState.updateMeshData(device: device)
        } catch {
            print("ERROR: Failed to update sliced mesh: \(error)")
        }
    }

    private func applyLeveling() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        do {
            try appState.applyLevelingRotation(device: device)
        } catch {
            print("ERROR: Failed to apply leveling: \(error)")
        }
    }

    private func updateSlicePlaneOnly() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let model = appState.model else { return }
        do {
            // Only update slice plane visualization without recalculating mesh
            if appState.slicingState.showPlanes && appState.slicingState.activePlane != nil {
                let bbox = model.boundingBox()
                let planeSize = Float(bbox.diagonal * 1.5)
                appState.slicePlaneData = try SlicePlaneData(
                    device: device,
                    slicingState: appState.slicingState,
                    modelCenter: bbox.center,
                    planeSize: planeSize
                )
            } else {
                appState.slicePlaneData = nil
            }
        } catch {
            print("ERROR: Failed to update slice plane: \(error)")
        }
    }

    private func loadFileOnStartup(_ url: URL) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ERROR: Metal device not available")
            return
        }

        appState.isLoading = true
        Task { @MainActor in
            do {
                try appState.loadFile(url, device: device)
                windowTitle = url.lastPathComponent

                // Update window title after a short delay to ensure window is ready
                DispatchQueue.main.async {
                    self.updateWindowTitle(url.lastPathComponent, representedURL: url)
                }

                RecentDocuments.shared.addDocument(url)
                try? appState.setupFileWatcher()
            } catch {
                print("ERROR: Failed to load file on startup: \(error)")
                // Drawn from here rather than left to the state change below, so
                // the message does not depend on when observation delivers it.
                handleLoadError(error, isAutoReload: false)
                // Nothing drawn, rather than the test cube this used to fall
                // back to: a failure must not be able to look like a success
                // (0484). See AppState.showFailedLoad.
                appState.showFailedLoad(of: url, error: error)
            }
        }
    }

    /// Find and update the window that contains this ContentView
    private func updateWindowTitle(_ title: String, representedURL: URL?) {
        // Find window by stored window number, or by checking if it's the key window
        let window: NSWindow?
        if windowNumber != 0 {
            window = NSApp.windows.first { $0.windowNumber == windowNumber }
        } else {
            // Fallback: use key window if we don't have a window number yet
            window = NSApp.keyWindow
        }

        if let window = window {
            window.title = title
            window.representedURL = representedURL
            if windowNumber == 0 {
                windowNumber = window.windowNumber
            }
            print("DEBUG: Updated window \(window.windowNumber) title to: \(title)")
        }
    }

    /// Capture the window number for this ContentView and set up notifications
    private func captureWindowAndSetupNotifications() {
        // Try to find our window
        if let window = NSApp.keyWindow, window.tabbingIdentifier == "GoSTLWindow" {
            windowNumber = window.windowNumber
            print("DEBUG: Captured window number: \(windowNumber)")
        }

        setupNotifications()
        setupGo3mfErrorNotification()
    }

    /// Set up notification listener for go3mf errors
    private func setupGo3mfErrorNotification() {
        go3mfErrorObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("Go3mfError"),
            object: nil,
            queue: .main
        ) { [self] notification in
            if let error = notification.object as? Go3mfError {
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        overlayError = .go3mf(error)
                    }
                }
            }
        }
    }

    private func setupNotifications() {
        // Handle window-specific LoadFileInWindow notification
        // This is used when File > Open detects an empty window
        let capturedWindowNumber = windowNumber
        print("DEBUG: Setting up notifications for window \(capturedWindowNumber)")

        // Don't set up notification if we don't have a valid window number
        guard capturedWindowNumber != 0 else {
            print("DEBUG: Skipping notification setup - no window number yet")
            return
        }

        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LoadFileInWindow"),
            object: nil,
            queue: .main
        ) { [weak appState] notification in
            guard let url = notification.object as? URL,
                  let appState = appState else { return }

            // Check if this notification is for our window
            if let targetWindowNumber = notification.userInfo?["windowNumber"] as? Int {
                // Only respond if we are the target window
                guard targetWindowNumber == capturedWindowNumber else {
                    print("DEBUG: Ignoring notification for window \(targetWindowNumber), we are \(capturedWindowNumber)")
                    return
                }
            } else {
                // No target window specified - ignore
                return
            }

            print("DEBUG: Loading file in window \(capturedWindowNumber): \(url.lastPathComponent)")

            // Load file using MainActor to ensure proper thread isolation
            Task { @MainActor in
                guard let device = MTLCreateSystemDefaultDevice() else {
                    print("ERROR: Metal device not available")
                    return
                }

                appState.isLoading = true
                do {
                    try appState.loadFile(url, device: device)

                    // Update window properties
                    if let window = NSApp.windows.first(where: { $0.windowNumber == capturedWindowNumber }) {
                        window.representedURL = url
                        window.title = url.lastPathComponent
                    }

                    RecentDocuments.shared.addDocument(url)
                    try? appState.setupFileWatcher()
                } catch {
                    print("ERROR: Failed to load file: \(error)")
                    appState.isLoading = false
                }
            }
        }
    }

    private func reloadModel() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        appState.reloadModel(device: device)
    }

    private func handleLoadError(_ error: Error, isAutoReload: Bool) {
        if let openscadError = error as? OpenSCADError {
            // For auto-reload errors, show overlay instead of modal dialog
            if isAutoReload {
                withAnimation(.easeInOut(duration: 0.3)) {
                    overlayError = .openSCAD(openscadError)
                }
            } else {
                // For initial load errors, also use overlay for consistency
                switch openscadError {
                case .emptyFile:
                    // Empty files are handled gracefully - no error dialog needed
                    break
                default:
                    withAnimation(.easeInOut(duration: 0.3)) {
                        overlayError = .openSCAD(openscadError)
                    }
                }
            }
        } else if let go3mfError = error as? Go3mfError {
            // Handle go3mf errors with overlay
            withAnimation(.easeInOut(duration: 0.3)) {
                overlayError = .go3mf(go3mfError)
            }
        } else {
            // For other errors, show modal dialog
            errorAlert = ErrorAlert(
                title: "Failed to Load File",
                message: error.localizedDescription
            )
        }
    }

    private func setupInitialState(loadTestCube: Bool = true) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ERROR: Metal device not available")
            return
        }

        do {
            // Load test cube if requested
            if loadTestCube {
                let testCube = createTestCube()
                try appState.loadModel(testCube, device: device)
                appState.modelInfo = ModelInfo(fileName: "test_cube.stl", model: testCube)
                print("Test cube loaded: \(testCube.triangleCount) triangles")
            }
        } catch {
            print("ERROR: Failed to initialize scene: \(error)")
        }
    }

    // Create a simple test cube (10x10x10 centered at origin)
    private func createTestCube() -> STLModel {
        var triangles: [Triangle] = []
        let size: Double = 50.0
        let half = size / 2.0

        // Bottom face (z = -half)
        triangles.append(Triangle(v1: Vector3(-half, -half, -half), v2: Vector3(half, half, -half), v3: Vector3(half, -half, -half)))
        triangles.append(Triangle(v1: Vector3(-half, -half, -half), v2: Vector3(-half, half, -half), v3: Vector3(half, half, -half)))

        // Top face (z = half)
        triangles.append(Triangle(v1: Vector3(-half, -half, half), v2: Vector3(half, -half, half), v3: Vector3(half, half, half)))
        triangles.append(Triangle(v1: Vector3(-half, -half, half), v2: Vector3(half, half, half), v3: Vector3(-half, half, half)))

        // Front face (y = -half)
        triangles.append(Triangle(v1: Vector3(-half, -half, -half), v2: Vector3(half, -half, -half), v3: Vector3(half, -half, half)))
        triangles.append(Triangle(v1: Vector3(-half, -half, -half), v2: Vector3(half, -half, half), v3: Vector3(-half, -half, half)))

        // Back face (y = half)
        triangles.append(Triangle(v1: Vector3(-half, half, -half), v2: Vector3(half, half, half), v3: Vector3(half, half, -half)))
        triangles.append(Triangle(v1: Vector3(-half, half, -half), v2: Vector3(-half, half, half), v3: Vector3(half, half, half)))

        // Left face (x = -half)
        triangles.append(Triangle(v1: Vector3(-half, -half, -half), v2: Vector3(-half, -half, half), v3: Vector3(-half, half, half)))
        triangles.append(Triangle(v1: Vector3(-half, -half, -half), v2: Vector3(-half, half, half), v3: Vector3(-half, half, -half)))

        // Right face (x = half)
        triangles.append(Triangle(v1: Vector3(half, -half, -half), v2: Vector3(half, half, -half), v3: Vector3(half, half, half)))
        triangles.append(Triangle(v1: Vector3(half, -half, -half), v2: Vector3(half, half, half), v3: Vector3(half, -half, half)))

        return STLModel(triangles: triangles, name: "test_cube")
    }
}

/// Error alert for displaying user-friendly error messages
struct ErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Loading overlay shown while waiting for file to load
struct LoadingOverlay: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)

            Text("Loading...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        )
    }
}

/// Overlay shown when an OpenSCAD file produces no geometry
struct EmptyFileOverlay: View {
    let fileName: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.6))

            Text("Empty Model")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text("The file produces no geometry")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
        )
    }
}

#Preview {
    ContentView()
}

/// Opens the menu panel when it has been folded away.
///
/// Styled like the panel it replaces so it reads as the same piece of chrome
/// rather than something new.
private struct MenuPanelButton: View {
	let action: () -> Void
	@State private var isHovering = false

	var body: some View {
		Button(action: action) {
			Image(systemName: "sidebar.left")
				.font(.system(size: 13, weight: .medium))
				.foregroundColor(.white.opacity(isHovering ? 1 : 0.75))
				.frame(width: 28, height: 28)
				.background(
					RoundedRectangle(cornerRadius: 8)
						.fill(.ultraThinMaterial)
						.shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
				)
		}
		.buttonStyle(.plain)
		.onHover { isHovering = $0 }
		.help("Show the panel")
	}
}

extension NSColor {
	/// The components Metal writes for this colour.
	///
	/// The drawable is `bgra8Unorm` rather than an sRGB format, so what is
	/// written is the display value itself and no conversion belongs here.
	var viewportComponents: SIMD4<Float> {
		let srgb = usingColorSpace(.sRGB) ?? self
		return SIMD4<Float>(
			Float(srgb.redComponent),
			Float(srgb.greenComponent),
			Float(srgb.blueComponent),
			1
		)
	}
}
