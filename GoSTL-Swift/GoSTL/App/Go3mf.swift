import Foundation

/// Get the user's shell PATH by running a login shell
/// - Returns: The full PATH string from the user's shell environment
private func getShellPath() -> String? {
    let shellProcess = Process()
    let pipe = Pipe()

    // Use login shell to get full PATH
    shellProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
    shellProcess.arguments = ["-l", "-c", "echo $PATH"]
    shellProcess.standardOutput = pipe
    shellProcess.standardError = FileHandle.nullDevice

    do {
        try shellProcess.run()
        shellProcess.waitUntilExit()

        if shellProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }
    } catch {
        // Fall through
    }

    return nil
}

/// Find the go3mf executable path
/// - Returns: Path to the go3mf executable, or nil if not found
private func findGo3mfExecutable() -> String? {
    // Common locations to check for go3mf on macOS
    let commonPaths = [
        "/usr/local/bin/go3mf",
        "/opt/homebrew/bin/go3mf",
        "/usr/bin/go3mf",
        NSHomeDirectory() + "/go/bin/go3mf",
        NSHomeDirectory() + "/.local/bin/go3mf"
    ]

    // Check common installation paths first
    for path in commonPaths {
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }

    // Try using shell to find it (handles PATH from shell profile)
    let shellProcess = Process()
    let pipe = Pipe()

    // Use login shell to get full PATH
    shellProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
    shellProcess.arguments = ["-l", "-c", "which go3mf"]
    shellProcess.standardOutput = pipe
    shellProcess.standardError = FileHandle.nullDevice

    do {
        try shellProcess.run()
        shellProcess.waitUntilExit()

        if shellProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }
    } catch {
        // Fall through
    }

    return nil
}

/// Opens the current file with go3mf
func openWithGo3mf(sourceFileURL: URL?) {
    guard let sourceURL = sourceFileURL else {
        print("No file loaded")
        return
    }

    // Find go3mf executable
    guard let go3mfPath = findGo3mfExecutable() else {
        print("go3mf not found. Please install go3mf first.")
        print("Checked: /usr/local/bin/go3mf, /opt/homebrew/bin/go3mf, ~/go/bin/go3mf")
        return
    }

    print("Opening \(sourceURL.path) with go3mf at \(go3mfPath)...")

    // Execute go3mf build <filename> --open
    let process = Process()
    process.executableURL = URL(fileURLWithPath: go3mfPath)
    process.arguments = ["build", sourceURL.path, "--open"]

    // Inherit the user's shell PATH so go3mf can find openscad and other tools
    var environment = ProcessInfo.processInfo.environment
    if let shellPath = getShellPath() {
        environment["PATH"] = shellPath
    }
    process.environment = environment

    do {
        try process.run()
        print("go3mf command launched successfully")
    } catch {
        print("Error launching go3mf: \(error)")
    }
}
