import SwiftUI
import AppKit

@main
struct GoSTLApp: App {
    @State private var recentDocuments = RecentDocuments.shared

    init() {
        print("DEBUG: GoSTLApp initializing...")

        // Ensure the app activates and comes to foreground
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            print("DEBUG: App activated")

            // Debug: Print all windows
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("DEBUG: Number of windows: \(NSApp.windows.count)")
                for (index, window) in NSApp.windows.enumerated() {
                    print("DEBUG: Window \(index): visible=\(window.isVisible), frame=\(window.frame)")
                }
            }

            // Check for command-line file argument
            GoSTLApp.handleCommandLineArguments()
        }
    }

    private static func handleCommandLineArguments() {
        let args = CommandLine.arguments
        // Skip the first argument (executable path)
        for arg in args.dropFirst() {
            // Skip Xcode debug arguments
            if arg.hasPrefix("-") {
                continue
            }

            // Check if it's an STL file
            let url = URL(fileURLWithPath: arg)
            if url.pathExtension.lowercased() == "stl" && FileManager.default.fileExists(atPath: url.path) {
                print("Loading file from command line: \(url.path)")
                // Post notification to load file after a short delay to ensure UI is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("LoadSTLFile"),
                        object: url
                    )
                }
                break // Only load the first file
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    print("DEBUG: ContentView appeared")
                }
        }
        .defaultSize(width: 1400, height: 900)
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
        }
    }

    // MARK: - File Operations

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "stl")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select an STL file to open"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            // Add to recent documents
            recentDocuments.addDocument(url)

            // Post notification to load file
            NotificationCenter.default.post(
                name: NSNotification.Name("LoadSTLFile"),
                object: url
            )
        }
    }

    private func openRecentFile(_ url: URL) {
        // Check if file still exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            recentDocuments.removeDocument(url)
            print("ERROR: File no longer exists: \(url.path)")
            return
        }

        // Post notification to load file
        NotificationCenter.default.post(
            name: NSNotification.Name("LoadSTLFile"),
            object: url
        )
    }
}
