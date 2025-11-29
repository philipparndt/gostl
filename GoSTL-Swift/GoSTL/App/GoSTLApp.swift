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
            // Add basic commands
            CommandGroup(replacing: .newItem) { }
        }
    }
}
