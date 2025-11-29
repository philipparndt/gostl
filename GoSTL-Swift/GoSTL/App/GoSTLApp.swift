import SwiftUI
import AppKit

@main
struct GoSTLApp: App {
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

            // Post notification to load file
            NotificationCenter.default.post(
                name: NSNotification.Name("LoadSTLFile"),
                object: url
            )
        }
    }
}
