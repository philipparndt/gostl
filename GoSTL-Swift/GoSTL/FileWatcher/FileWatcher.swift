import Foundation

/// Watches files for changes and triggers callbacks with debouncing
class FileWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.gostl.filewatcher")
    private var debounceTimers: [String: DispatchWorkItem] = [:]
    private var callback: ((URL) -> Void)?

    /// Whether the watcher is paused (ignores events)
    var isPaused: Bool = false

    /// Initialize a file watcher with debounce interval
    /// - Parameter debounceInterval: Time to wait before triggering callback (in seconds)
    init(debounceInterval: TimeInterval = 0.5) {
        self.debounceInterval = debounceInterval
    }

    /// Start watching files for changes
    /// - Parameters:
    ///   - files: Array of file URLs to watch
    ///   - callback: Closure to call when a file changes (receives the changed file URL)
    /// - Throws: Error if watching cannot be set up
    func watch(files: [URL], callback: @escaping (URL) -> Void) throws {
        // Stop any existing watching
        stop()

        self.callback = callback

        for fileURL in files {
            let path = fileURL.path

            // Open file descriptor for monitoring
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else {
                print("ERROR: Failed to open file for watching: \(path)")
                continue
            }

            fileDescriptors.append(fd)

            // Create dispatch source to monitor file changes
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib],
                queue: queue
            )

            source.setEventHandler { [weak self] in
                self?.handleFileChange(fileURL: fileURL)
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
            sources.append(source)
        }

        print("Watching \(files.count) file(s) for changes:")
        for file in files {
            print("  - \(file.path)")
        }
    }

    /// Handle file change event with debouncing
    private func handleFileChange(fileURL: URL) {
        // Ignore events while paused
        if isPaused {
            return
        }

        let path = fileURL.path

        // Cancel existing timer for this file if any
        debounceTimers[path]?.cancel()

        // Create new debounced callback
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isPaused else { return }
            print("File changed: \(fileURL.lastPathComponent)")
            self.callback?(fileURL)
        }

        debounceTimers[path] = workItem

        // Schedule callback after debounce interval
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    /// Stop watching all files
    func stop() {
        // Cancel all dispatch sources
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        fileDescriptors.removeAll()

        // Cancel all pending timers
        for (_, timer) in debounceTimers {
            timer.cancel()
        }
        debounceTimers.removeAll()
    }

    deinit {
        stop()
    }
}
