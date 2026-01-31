import SwiftUI
import AppKit

/// Manages file opens during app launch with proper synchronization
@MainActor
final class FileOpenCoordinator {
    static let shared = FileOpenCoordinator()

    /// Files queued during launch (before first window ready)
    private var pendingFiles: [URL] = []

    /// Whether app launch is complete (applicationDidFinishLaunching called)
    private var launchComplete = false

    /// Whether the first window has claimed files
    private var firstWindowReady = false

    /// Whether we're expecting files from Finder (detected via Apple Events)
    private var expectingFinderFiles = false

    /// Continuation for waiting on launch completion
    private var waitContinuation: CheckedContinuation<URL?, Never>?

    private init() {}

    /// Called early in launch to indicate we're being opened with files
    func setExpectingFiles() {
        print("DEBUG: setExpectingFiles called")
        expectingFinderFiles = true
    }

    /// Called from applicationDidFinishLaunching
    func markLaunchComplete() {
        print("DEBUG: markLaunchComplete, pendingFiles=\(pendingFiles.count), expectingFinderFiles=\(expectingFinderFiles)")
        launchComplete = true

        // If ContentView is waiting, resolve with pending file or nil
        if let continuation = waitContinuation {
            let file = pendingFiles.isEmpty ? nil : pendingFiles.removeFirst()
            print("DEBUG: Resolving waiting continuation with: \(file?.lastPathComponent ?? "nil")")
            continuation.resume(returning: file)
            waitContinuation = nil
            firstWindowReady = true
        }
    }

    /// Called from application(_:open:) when Finder opens files
    func addFile(_ url: URL) {
        print("DEBUG: addFile(\(url.lastPathComponent)), launchComplete=\(launchComplete), firstWindowReady=\(firstWindowReady)")

        // If someone is waiting for files (during launch), give them this one
        if let continuation = waitContinuation {
            print("DEBUG: Resolving waiting continuation with: \(url.lastPathComponent)")
            continuation.resume(returning: url)
            waitContinuation = nil
            firstWindowReady = true
            return
        }

        // During launch, queue for first window
        if !launchComplete {
            pendingFiles.append(url)
            print("DEBUG: Queued file for launch, pendingFiles=\(pendingFiles.count)")
            return
        }

        // App is running - try to load in key window if empty, otherwise create new window
        if let keyWindow = NSApp.keyWindow,
           keyWindow.tabbingIdentifier == "GoSTLWindow",
           keyWindow.representedURL == nil {
            // Key window is empty - load file there via notification
            print("DEBUG: Loading in empty key window")
            NotificationCenter.default.post(
                name: NSNotification.Name("LoadFileInWindow"),
                object: url,
                userInfo: ["windowNumber": keyWindow.windowNumber]
            )
        } else {
            // Create new window
            print("DEBUG: Creating new window for file")
            createNewWindow(for: url)
        }
    }

    /// Called from ContentView.onAppear to get the initial file (if any)
    /// Returns immediately if launch is complete, otherwise waits
    func claimInitialFile() async -> URL? {
        print("DEBUG: claimInitialFile, launchComplete=\(launchComplete), expectingFinderFiles=\(expectingFinderFiles), pendingFiles=\(pendingFiles.count)")

        // If we already have a pending file, return it immediately
        if !pendingFiles.isEmpty {
            firstWindowReady = true
            let file = pendingFiles.removeFirst()
            print("DEBUG: Claiming pending file: \(file.lastPathComponent)")
            return file
        }

        // If we're expecting files from Finder, wait for them
        if expectingFinderFiles && !launchComplete {
            print("DEBUG: Waiting for Finder files...")
            return await withCheckedContinuation { continuation in
                self.waitContinuation = continuation
            }
        }

        // No files expected or launch complete - return nil
        firstWindowReady = true
        print("DEBUG: No pending files, returning nil")
        return nil
    }

    /// Create a new tab/window for a file (when app is already running)
    func createNewTab(for url: URL) {
        print("DEBUG: Creating new tab for \(url.lastPathComponent)")
        createTab(contentView: ContentView(fileURL: url), title: url.lastPathComponent, representedURL: url)
    }

    /// Create an empty tab
    func createEmptyTab(title: String) {
        print("DEBUG: Creating empty tab: \(title)")
        createTab(contentView: ContentView(fileURL: nil), title: title, representedURL: nil)
    }

    /// Internal helper to create a tab with given content
    private func createTab(contentView: ContentView, title: String, representedURL: URL?) {
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.representedURL = representedURL
        window.setContentSize(NSSize(width: 1400, height: 900))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "GoSTLWindow"
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true

        // Find an existing GoSTL window to add this as a tab
        var existingWindow: NSWindow? = nil
        for w in NSApp.windows {
            if w.tabbingIdentifier == "GoSTLWindow" && w.isVisible && w != window {
                existingWindow = w
                break
            }
        }

        if let existingWindow = existingWindow {
            // Add as a tab to existing window
            print("DEBUG: Adding as tab to existing window")
            existingWindow.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        } else {
            // No existing window - just show the new window
            print("DEBUG: No existing window found, showing as new window")
            window.makeKeyAndOrderFront(nil)
        }
    }

    // Legacy wrapper for compatibility
    private func createNewWindow(for url: URL) {
        createNewTab(for: url)
    }
}

/// Application delegate
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static var commandLineFileURL: URL?

    func applicationWillFinishLaunching(_ notification: Notification) {
        print("DEBUG: applicationWillFinishLaunching")

        // Check if we're being launched to open files via Apple Events
        // This happens before application(_:open:) is called
        if let appleEvent = NSAppleEventManager.shared().currentAppleEvent,
           appleEvent.eventClass == AEEventClass(kCoreEventClass),
           appleEvent.eventID == AEEventID(kAEOpenDocuments) {
            print("DEBUG: Detected open-documents Apple Event")
            FileOpenCoordinator.shared.setExpectingFiles()
        }

        // Parse command line arguments
        for arg in CommandLine.arguments.dropFirst() {
            if arg.hasPrefix("-") { continue }
            let url = URL(fileURLWithPath: arg)
            let ext = url.pathExtension.lowercased()
            if ["stl", "3mf", "scad", "yaml", "yml"].contains(ext) && FileManager.default.fileExists(atPath: url.path) {
                AppDelegate.commandLineFileURL = url
                print("DEBUG: Command line file: \(url.lastPathComponent)")
                break
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("DEBUG: applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        configureAllWindows()

        // Defer launch completion to allow application(_:open:) to be processed first
        // Use nested async to ensure we're after any pending Apple Events
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                print("DEBUG: Deferred markLaunchComplete")
                FileOpenCoordinator.shared.markLaunchComplete()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChange),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
    }

    @objc private func windowDidChange(_ notification: Notification) {
        configureAllWindows()
    }

    /// Handle files opened from Finder
    func application(_ application: NSApplication, open urls: [URL]) {
        print("DEBUG: application(_:open:) called with \(urls.count) files")
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ["stl", "3mf", "scad", "yaml", "yml"].contains(ext) else { continue }
            FileOpenCoordinator.shared.addFile(url)
        }
    }

    private func configureAllWindows() {
        for window in NSApp.windows {
            // Skip non-standard windows
            guard !window.isSheet, window.styleMask.contains(.titled) else { continue }

            // Ensure consistent tabbingIdentifier
            if window.tabbingIdentifier != "GoSTLWindow" {
                window.tabbingIdentifier = "GoSTLWindow"
            }
            window.tabbingMode = .preferred
            if window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
        }
    }
}

@main
struct GoSTLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.appState) private var appState

    private var recentDocuments: RecentDocuments {
        RecentDocuments.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView(fileURL: AppDelegate.commandLineFileURL)
                .onAppear {
                    configureWindowForTabbing()
                }
        }
        // Prevent SwiftUI from auto-creating windows for external events
        // We handle file opens manually via application(_:open:)
        .handlesExternalEvents(matching: [])
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1400, height: 900)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    openNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Open...") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Menu("Open Recent") {
                    ForEach(recentDocuments.recentURLs, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            openRecentFile(url)
                        }
                    }

                    if !recentDocuments.recentURLs.isEmpty {
                        Divider()
                        Button("Clear Menu") {
                            recentDocuments.clearRecents()
                        }
                    }
                }
                .disabled(recentDocuments.recentURLs.isEmpty)

                Divider()

                Button("Save") {
                    saveFile()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appState?.canSave != true || appState?.hasSaveDestination != true)

                Button("Save As...") {
                    saveFileAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(appState?.model == nil)

                Divider()

                Button("Reload") {
                    NotificationCenter.default.post(name: NSNotification.Name("ReloadModel"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState?.sourceFileURL == nil)
            }

            CommandGroup(before: .toolbar) {
                Toggle("Info Panel", isOn: Binding(
                    get: { appState?.showModelInfo ?? true },
                    set: { appState?.showModelInfo = $0 }
                ))
                .keyboardShortcut("i", modifiers: .command)

                Menu("Wireframe") {
                    Button("Off") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetWireframeMode"), object: WireframeMode.off)
                    }
                    Button("All") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetWireframeMode"), object: WireframeMode.all)
                    }
                    Button("Edge") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetWireframeMode"), object: WireframeMode.edge)
                    }
                }

                Button("Cycle Wireframe Mode") {
                    NotificationCenter.default.post(name: NSNotification.Name("CycleWireframeMode"), object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Menu("Grid") {
                    Button("Off") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetGridMode"), object: GridMode.off)
                    }
                    Button("Bottom") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetGridMode"), object: GridMode.bottom)
                    }
                    Button("All Sides") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetGridMode"), object: GridMode.allSides)
                    }
                    Button("1mm Grid") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetGridMode"), object: GridMode.oneMM)
                    }
                }

                Button("Cycle Grid Mode") {
                    NotificationCenter.default.post(name: NSNotification.Name("CycleGridMode"), object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Divider()

                Menu("Build Plate") {
                    Button("Off") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetBuildPlate"), object: BuildPlate.off)
                    }

                    Divider()

                    Text("Bambu Lab")
                    Button("X1C (256³)") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetBuildPlate"), object: BuildPlate.bambuLabX1C)
                    }
                    Button("P1S (256³)") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetBuildPlate"), object: BuildPlate.bambuLabP1S)
                    }
                    Button("A1 (256³)") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetBuildPlate"), object: BuildPlate.bambuLabA1)
                    }
                    Button("A1 mini (180³)") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetBuildPlate"), object: BuildPlate.bambuLabA1Mini)
                    }
                    Button("H2D (450³)") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetBuildPlate"), object: BuildPlate.bambuLabH2D)
                    }

                    Divider()

                    Text("Prusa")
                    Button("MK4 (250x210x220)") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetBuildPlate"), object: BuildPlate.prusa_mk4)
                    }
                    Button("Mini (180³)") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetBuildPlate"), object: BuildPlate.prusa_mini)
                    }

                    Divider()

                    Text("Voron")
                    Button("V0 (120³)") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetBuildPlate"), object: BuildPlate.voron_v0)
                    }
                    Button("2.4 (350³)") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetBuildPlate"), object: BuildPlate.voron_24)
                    }

                    Divider()

                    Text("Creality")
                    Button("Ender 3 (220x220x250)") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetBuildPlate"), object: BuildPlate.ender3)
                    }
                }

                Button("Cycle Build Plate") {
                    NotificationCenter.default.post(name: NSNotification.Name("CycleBuildPlate"), object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)

                Divider()

                Toggle("Slicing", isOn: Binding(
                    get: { appState?.slicingState.isVisible ?? false },
                    set: { _ in appState?.slicingState.toggleVisibility() }
                ))
                .keyboardShortcut("x", modifiers: [.command, .shift])

                Divider()

                Toggle("Show Diameter", isOn: Binding(
                    get: { appState?.measurementSystem.showDiameter ?? false },
                    set: { appState?.measurementSystem.showDiameter = $0 }
                ))

                Divider()

                Menu("Camera") {
                    Button("Front") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetCameraPreset"), object: CameraPreset.front)
                    }
                    .keyboardShortcut("1", modifiers: .command)

                    Button("Back") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetCameraPreset"), object: CameraPreset.back)
                    }
                    .keyboardShortcut("2", modifiers: .command)

                    Button("Left") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetCameraPreset"), object: CameraPreset.left)
                    }
                    .keyboardShortcut("3", modifiers: .command)

                    Button("Right") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetCameraPreset"), object: CameraPreset.right)
                    }
                    .keyboardShortcut("4", modifiers: .command)

                    Button("Top") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetCameraPreset"), object: CameraPreset.top)
                    }
                    .keyboardShortcut("5", modifiers: .command)

                    Button("Bottom") {
                        NotificationCenter.default.post(name: NSNotification.Name("SetCameraPreset"), object: CameraPreset.bottom)
                    }
                    .keyboardShortcut("6", modifiers: .command)

                    Divider()

                    Button("Reset View") {
                        NotificationCenter.default.post(name: NSNotification.Name("ResetCamera"), object: nil)
                    }
                    .keyboardShortcut("0", modifiers: .command)
                }
            }

            CommandMenu("Tools") {
                Button("Measure Distance") {
                    NotificationCenter.default.post(name: NSNotification.Name("StartMeasurement"), object: MeasurementType.distance)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Measure Angle") {
                    NotificationCenter.default.post(name: NSNotification.Name("StartMeasurement"), object: MeasurementType.angle)
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Measure Radius") {
                    NotificationCenter.default.post(name: NSNotification.Name("StartMeasurement"), object: MeasurementType.radius)
                }

                Divider()

                Button("Select Triangles") {
                    NotificationCenter.default.post(name: NSNotification.Name("StartMeasurement"), object: MeasurementType.triangleSelect)
                }
                .keyboardShortcut("t", modifiers: [])

                Divider()

                Button("Level Object") {
                    NotificationCenter.default.post(name: NSNotification.Name("StartLeveling"), object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Undo Leveling") {
                    NotificationCenter.default.post(name: NSNotification.Name("UndoLeveling"), object: nil)
                }
                .disabled(appState?.levelingState.canUndo != true)

                Divider()

                Button("Clear All Measurements") {
                    NotificationCenter.default.post(name: NSNotification.Name("ClearMeasurements"), object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Divider()

                Button("Copy as OpenSCAD") {
                    NotificationCenter.default.post(name: NSNotification.Name("CopyMeasurementsAsOpenSCAD"), object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Copy as OpenSCAD (Closed Solid)") {
                    NotificationCenter.default.post(name: NSNotification.Name("CopyMeasurementsAsOpenSCADClosed"), object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift, .option])

                Button("Copy as Polygon") {
                    NotificationCenter.default.post(name: NSNotification.Name("CopyMeasurementsAsPolygon"), object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("Change Material") {
                    NotificationCenter.default.post(name: NSNotification.Name("CycleMaterial"), object: nil)
                }
                .keyboardShortcut("m", modifiers: .command)

                Divider()

                Button("Open with go3mf") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenWithGo3mf"), object: nil)
                }
                .keyboardShortcut("o", modifiers: [])

                Button("Open in OpenSCAD") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenInOpenSCAD"), object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(appState?.isOpenSCAD != true)
            }

            CommandGroup(replacing: .appInfo) {
                Button("About GoSTL") {
                    showAboutPanel()
                }
            }
        }
    }

    private func showAboutPanel() {
        let alert = NSAlert()
        alert.messageText = "GoSTL"
        alert.informativeText = """
            \(AppVersion.fullVersion)

            3D STL Viewer and OpenSCAD Renderer

            \(AppVersion.version != "dev" ? "Commit: \(AppVersion.gitCommit)\nBuilt: \(AppVersion.buildDate)" : "")
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "stl")!,
            .init(filenameExtension: "3mf")!,
            .init(filenameExtension: "scad")!,
            .init(filenameExtension: "yaml")!,
            .init(filenameExtension: "yml")!
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                RecentDocuments.shared.addDocument(url)
                self.openFileInWindowOrNew(url)
            }
        }
    }

    private func saveFile() {
        guard let appState = appState else { return }
        do {
            try appState.saveModel()
            if let savedURL = appState.savedFileURL, let window = NSApp.keyWindow {
                window.title = savedURL.lastPathComponent
                window.representedURL = savedURL
                recentDocuments.addDocument(savedURL)
            }
        } catch {
            showSaveError(error)
        }
    }

    private func saveFileAs() {
        guard let appState = appState else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "stl")!]
        panel.nameFieldStringValue = suggestFileName(for: appState)

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try appState.saveModelAs(to: url)
                if let window = NSApp.keyWindow {
                    window.title = url.lastPathComponent
                    window.representedURL = url
                }
                self.recentDocuments.addDocument(url)
            } catch {
                self.showSaveError(error)
            }
        }
    }

    private func suggestFileName(for appState: AppState) -> String {
        if let savedURL = appState.savedFileURL { return savedURL.lastPathComponent }
        if let sourceURL = appState.sourceFileURL {
            return "\(sourceURL.deletingPathExtension().lastPathComponent).stl"
        }
        return "model.stl"
    }

    private func showSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to Save"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func openRecentFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            RecentDocuments.shared.removeDocument(url)
            return
        }
        openFileInWindowOrNew(url)
    }

    private func openFileInWindowOrNew(_ url: URL) {
        // If key window is empty, load there
        if let keyWindow = NSApp.keyWindow,
           keyWindow.tabbingIdentifier == "GoSTLWindow",
           keyWindow.representedURL == nil {
            NotificationCenter.default.post(
                name: NSNotification.Name("LoadFileInWindow"),
                object: url,
                userInfo: ["windowNumber": keyWindow.windowNumber]
            )
            return
        }
        // Create new window
        FileOpenCoordinator.shared.addFile(url)
    }

    private func openNewTab() {
        FileOpenCoordinator.shared.createEmptyTab(title: nextEmptyWindowTitle())
    }

    private func configureWindowForTabbing() {
        DispatchQueue.main.async {
            // Configure ALL windows to use the same tabbing identifier
            // This ensures SwiftUI-created windows can tab with manually created ones
            for window in NSApp.windows {
                // Skip non-standard windows (panels, sheets, etc.)
                guard window.isKind(of: NSWindow.self),
                      !window.isSheet,
                      window.styleMask.contains(.titled) else { continue }

                // Set consistent tabbingIdentifier for all main windows
                if window.tabbingIdentifier != "GoSTLWindow" {
                    window.tabbingIdentifier = "GoSTLWindow"
                }
                window.tabbingMode = .preferred
                window.titlebarSeparatorStyle = .none
                window.titlebarAppearsTransparent = true
                if !window.styleMask.contains(.fullSizeContentView) {
                    window.styleMask.insert(.fullSizeContentView)
                }
            }
        }
    }

    private func nextEmptyWindowTitle() -> String {
        let emptyPattern = /^Empty (\d+)$/
        var usedNumbers: Set<Int> = []
        for window in NSApp.windows where window.tabbingIdentifier == "GoSTLWindow" {
            if let match = window.title.wholeMatch(of: emptyPattern),
               let number = Int(match.1) {
                usedNumbers.insert(number)
            }
        }
        var nextNumber = 1
        while usedNumbers.contains(nextNumber) { nextNumber += 1 }
        return "Empty \(nextNumber)"
    }
}
