import SwiftUI
import AppKit

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
            if (ext == "stl" || ext == "scad") && FileManager.default.fileExists(atPath: url.path) {
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
    }
}

@main
struct GoSTLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var openWindows: [UUID: URL] = [:]

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
        .defaultSize(width: 1400, height: 900)
        .defaultPosition(.center)
        .onChange(of: NSApp.windows) { _, _ in
            // Save window state whenever windows change
            saveCurrentWindowState()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
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
            }

            // View menu
            CommandMenu("View") {
                Button("Toggle Wireframe") {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleWireframe"), object: nil)
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

                Button("Toggle Slicing") {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleSlicing"), object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

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
                    .keyboardShortcut("r", modifiers: .command)
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
                // Using 'c' for radius (circle)

                Divider()

                Button("Clear All Measurements") {
                    NotificationCenter.default.post(name: NSNotification.Name("ClearMeasurements"), object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Divider()

                Button("Change Material") {
                    NotificationCenter.default.post(name: NSNotification.Name("CycleMaterial"), object: nil)
                }
                .keyboardShortcut("m", modifiers: .command)
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
            .init(filenameExtension: "scad")!
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select an STL or OpenSCAD file to open"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            // Add to recent documents
            recentDocuments.addDocument(url)

            // Create new window for this file
            openNewWindow(for: url)
        }
    }

    private func openRecentFile(_ url: URL) {
        // Check if file still exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            recentDocuments.removeDocument(url)
            print("ERROR: File no longer exists: \(url.path)")
            return
        }

        // Create new window for this file
        openNewWindow(for: url)
    }

    private func openNewWindow(for url: URL) {
        DispatchQueue.main.async {
            // Check if main window exists and has only the test cube (empty state)
            if let mainWindow = NSApp.mainWindow,
               mainWindow.tabbingIdentifier == "GoSTLWindow",
               self.isEmptyWindow(mainWindow) {
                // Load in existing empty window instead of creating new one
                NotificationCenter.default.post(
                    name: NSNotification.Name("LoadSTLFile"),
                    object: url
                )
                return
            }

            // Create a new NSWindow with ContentView
            let contentView = ContentView(fileURL: url)
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = url.lastPathComponent
            window.representedURL = url
            window.setContentSize(NSSize(width: 1400, height: 900))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]

            // Configure for tabbing
            window.tabbingMode = .preferred
            window.tabbingIdentifier = "GoSTLWindow"

            // Show the window
            window.makeKeyAndOrderFront(nil)

            // Add to existing tab group if tab bar is visible
            if let mainWindow = NSApp.mainWindow,
               mainWindow.tabbingIdentifier == "GoSTLWindow" {
                mainWindow.addTabbedWindow(window, ordered: .above)
            }
        }
    }

    private func isEmptyWindow(_ window: NSWindow) -> Bool {
        // A window is considered empty if it doesn't represent a file
        return window.representedURL == nil
    }

    private func configureWindowForTabbing() {
        DispatchQueue.main.async {
            // Configure all windows to support tabbing
            for window in NSApp.windows {
                window.tabbingMode = .preferred
                window.tabbingIdentifier = "GoSTLWindow"
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
}
