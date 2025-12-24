import SwiftUI
import AppKit

/// Manages pending file opens for the app
/// Handles files from Finder, command line, and File > Open
@MainActor
final class FileOpenManager {
    static let shared = FileOpenManager()

    /// Queue of files to open (from Finder double-click before app is ready)
    private var pendingFiles: [URL] = []

    /// Whether the first window has finished initializing
    private var firstWindowReady = false

    /// Lock for thread safety
    private let lock = NSLock()

    private init() {}

    /// Queue a file to be opened (called from AppDelegate)
    func queueFile(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }

        if firstWindowReady {
            // App is already running - create new window directly
            createNewWindow(for: url)
        } else {
            // App is launching - queue for first window to pick up
            pendingFiles.append(url)
        }
    }

    /// Called by the first ContentView when it's ready
    /// Returns the first pending file (if any) for the first window to load
    func claimPendingFileForFirstWindow() -> URL? {
        lock.lock()
        defer { lock.unlock() }

        firstWindowReady = true

        // Take the first pending file for this window
        if !pendingFiles.isEmpty {
            return pendingFiles.removeFirst()
        }
        return nil
    }

    /// Check if there are remaining pending files (for creating additional windows)
    func hasMorePendingFiles() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !pendingFiles.isEmpty
    }

    /// Create windows for any remaining pending files
    func createWindowsForRemainingFiles() {
        lock.lock()
        let files = pendingFiles
        pendingFiles.removeAll()
        lock.unlock()

        for url in files {
            createNewWindow(for: url)
        }
    }

    /// Create a new window with the given file URL
    private func createNewWindow(for url: URL) {
        let contentView = ContentView(fileURL: url)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = url.lastPathComponent
        window.representedURL = url
        window.setContentSize(NSSize(width: 1400, height: 900))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "GoSTLWindow"
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true

        // Show the window
        window.makeKeyAndOrderFront(nil)

        // Add to existing tab group if tab bar is visible
        if let mainWindow = NSApp.mainWindow,
           mainWindow != window,
           mainWindow.tabbingIdentifier == "GoSTLWindow" {
            mainWindow.addTabbedWindow(window, ordered: .above)
        }
    }
}

/// Application delegate for handling command line arguments and app lifecycle
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static var commandLineFileURL: URL?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Parse command line arguments before windows are created
        for arg in CommandLine.arguments.dropFirst() {
            if arg.hasPrefix("-") { continue }
            let url = URL(fileURLWithPath: arg)
            let ext = url.pathExtension.lowercased()
            if ["stl", "3mf", "scad", "yaml", "yml"].contains(ext) && FileManager.default.fileExists(atPath: url.path) {
                AppDelegate.commandLineFileURL = url
                break
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activate the app
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)

        // Set initial window title if no file was opened
        if AppDelegate.commandLineFileURL == nil,
           let window = NSApp.windows.first,
           window.representedURL == nil {
            window.title = "Empty 1"
        }

        // Configure initial window
        configureAllWindows()

        // Observe window changes to reapply title bar configuration
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChange),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChange),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        // After a brief delay, create windows for any remaining pending files
        // (files opened via Finder that weren't claimed by the first window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            FileOpenManager.shared.createWindowsForRemainingFiles()
        }
    }

    @objc private func windowDidChange(_ notification: Notification) {
        configureAllWindows()
    }

    /// Handle files opened from Finder (double-click, Open With, drag to dock icon)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ["stl", "3mf", "scad", "yaml", "yml"].contains(ext) else { continue }

            // Queue the file for opening
            FileOpenManager.shared.queueFile(url)
        }
    }

    private func configureAllWindows() {
        // Only configure our app windows, not system panels (NSOpenPanel, NSSavePanel, etc.)
        for window in NSApp.windows where window.tabbingIdentifier == "GoSTLWindow" {
            // Only modify if needed to avoid triggering additional notifications
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
    @State private var openWindows: [UUID: URL] = [:]
    @FocusedValue(\.appState) private var appState

    private var recentDocuments: RecentDocuments {
        RecentDocuments.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView(fileURL: AppDelegate.commandLineFileURL)
                .onAppear {
                    configureWindowForTabbing()
                    saveCurrentWindowState()
                }
        }
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

                // Open Recent submenu
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

            // Add items to the system View menu
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

            // Tools menu
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
            }

            // Help menu with About
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

    // MARK: - File Operations

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
        panel.message = "Select an STL, 3MF, OpenSCAD, or go3mf YAML file to open"

        panel.begin { response in
            guard response == .OK else { return }

            for url in panel.urls {
                RecentDocuments.shared.addDocument(url)
                self.openNewWindow(for: url)
            }
        }
    }

    private func saveFile() {
        guard let appState = appState else { return }

        do {
            try appState.saveModel()

            // Update window title and represented URL
            if let savedURL = appState.savedFileURL,
               let window = NSApp.keyWindow {
                window.title = savedURL.lastPathComponent
                window.representedURL = savedURL

                // Add to recent documents
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
        panel.message = "Save STL file"
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                try appState.saveModelAs(to: url)

                // Update window title and represented URL
                if let window = NSApp.keyWindow {
                    window.title = url.lastPathComponent
                    window.representedURL = url
                }

                // Add to recent documents
                self.recentDocuments.addDocument(url)
            } catch {
                self.showSaveError(error)
            }
        }
    }

    private func suggestFileName(for appState: AppState) -> String {
        // Use saved filename if available
        if let savedURL = appState.savedFileURL {
            return savedURL.lastPathComponent
        }

        // Use source filename, converting extension to .stl if needed
        if let sourceURL = appState.sourceFileURL {
            let baseName = sourceURL.deletingPathExtension().lastPathComponent
            return "\(baseName).stl"
        }

        // Default name
        return "model.stl"
    }

    private func showSaveError(_ error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Failed to Save"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func openRecentFile(_ url: URL) {
        // Check if file still exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            RecentDocuments.shared.removeDocument(url)
            print("ERROR: File no longer exists: \(url.path)")
            return
        }

        // Create new window for this file
        openNewWindow(for: url)
    }

    private func openNewWindow(for url: URL) {
        DispatchQueue.main.async {
            // Check if the key window is "empty" (no file loaded, just test cube)
            if let keyWindow = NSApp.keyWindow,
               keyWindow.tabbingIdentifier == "GoSTLWindow",
               keyWindow.representedURL == nil {
                // Load file into the existing empty window
                // Post a window-specific notification with the window identifier
                NotificationCenter.default.post(
                    name: NSNotification.Name("LoadFileInWindow"),
                    object: url,
                    userInfo: ["windowNumber": keyWindow.windowNumber]
                )
                return
            }

            // Create a new window
            let contentView = ContentView(fileURL: url)
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = url.lastPathComponent
            window.representedURL = url
            window.setContentSize(NSSize(width: 1400, height: 900))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]

            // Configure for tabbing and title bar appearance
            window.tabbingMode = .preferred
            window.tabbingIdentifier = "GoSTLWindow"
            window.titlebarSeparatorStyle = .none
            window.titlebarAppearsTransparent = true

            // Show the window
            window.makeKeyAndOrderFront(nil)

            // Add to existing tab group if tab bar is visible
            if let mainWindow = NSApp.mainWindow,
               mainWindow != window,
               mainWindow.tabbingIdentifier == "GoSTLWindow" {
                mainWindow.addTabbedWindow(window, ordered: .above)
            }
        }
    }

    private func openNewTab() {
        DispatchQueue.main.async {
            // Create a new NSWindow with ContentView (no file URL = test cube)
            let contentView = ContentView(fileURL: nil)
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = self.nextEmptyWindowTitle()
            window.setContentSize(NSSize(width: 1400, height: 900))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]

            // Configure for tabbing and title bar appearance
            window.tabbingMode = .preferred
            window.tabbingIdentifier = "GoSTLWindow"
            window.titlebarSeparatorStyle = .none
            window.titlebarAppearsTransparent = true

            // Show the window
            window.makeKeyAndOrderFront(nil)

            // Add to existing tab group if tab bar is visible
            if let mainWindow = NSApp.mainWindow,
               mainWindow != window,
               mainWindow.tabbingIdentifier == "GoSTLWindow" {
                mainWindow.addTabbedWindow(window, ordered: .above)
            }
        }
    }

    private func configureWindowForTabbing() {
        DispatchQueue.main.async {
            // Configure only our app windows, not system panels (NSOpenPanel, NSSavePanel, etc.)
            for window in NSApp.windows where window.tabbingIdentifier == "GoSTLWindow" {
                // Only modify if needed to avoid triggering additional notifications
                if window.tabbingMode != .preferred {
                    window.tabbingMode = .preferred
                }
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

    private func saveCurrentWindowState() {
        DispatchQueue.main.async {
            // Get all windows with represented files
            let openFileURLs = NSApp.windows
                .filter { $0.tabbingIdentifier == "GoSTLWindow" }
                .compactMap { $0.representedURL }

            // Save to RecentDocuments
            RecentDocuments.shared.saveOpenWindows(openFileURLs)
        }
    }

    private func nextEmptyWindowTitle() -> String {
        // Find existing "Empty N" windows and determine the next number
        let emptyPattern = /^Empty (\d+)$/
        var usedNumbers: Set<Int> = []

        for window in NSApp.windows where window.tabbingIdentifier == "GoSTLWindow" {
            if let match = window.title.wholeMatch(of: emptyPattern),
               let number = Int(match.1) {
                usedNumbers.insert(number)
            }
        }

        // Find the smallest unused number starting from 1
        var nextNumber = 1
        while usedNumbers.contains(nextNumber) {
            nextNumber += 1
        }

        return "Empty \(nextNumber)"
    }
}
