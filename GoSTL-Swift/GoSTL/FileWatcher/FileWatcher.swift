import Foundation

/// File metadata used to detect changes (modification time + size)
private struct FileFingerprint: Equatable {
    let modificationDate: Date
    let size: UInt64

    init?(url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date,
              let fileSize = attrs[.size] as? UInt64 else {
            return nil
        }
        self.modificationDate = modDate
        self.size = fileSize
    }
}

/// Watches files for changes using file system metadata to detect actual changes
///
/// Every piece of mutable state below belongs to `queue`. The dispatch sources
/// already delivered their events there; `watch` and `stop` are called from the
/// main thread and now hop onto it too, so the sources array and the
/// fingerprints are only ever touched from one serial queue. That confinement
/// is what makes the `@unchecked Sendable` below true rather than merely quiet
/// — before it, a `stop()` from the main thread could empty the array while an
/// event handler was walking it.
class FileWatcher: @unchecked Sendable {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private let queue = DispatchQueue(label: "com.gostl.filewatcher")
    private var callback: ((URL) -> Void)?
    private var fileFingerprints: [String: FileFingerprint] = [:]

    /// Whether the watcher is paused (ignores events)
    var isPaused: Bool = false

    /// Debounce: track last callback time per file to prevent rapid successive triggers
    private var lastCallbackTime: [String: Date] = [:]

    /// Minimum interval between callbacks for the same file (in seconds)
    private let debounceInterval: TimeInterval = 0.5

    init() {}

    /// Start watching files for changes
    /// - Parameters:
    ///   - files: Array of file URLs to watch
    ///   - callback: Closure to call when a file changes (receives the changed file URL)
    /// - Throws: Error if watching cannot be set up
    func watch(files: [URL], callback: @escaping (URL) -> Void) throws {
        queue.sync { watchOnQueue(files: files, callback: callback) }
    }

    /// The body of `watch`, on the queue that owns the state.
    private func watchOnQueue(files: [URL], callback: @escaping (URL) -> Void) {
        stopOnQueue()

        self.callback = callback

        // Store initial fingerprints
        for fileURL in files {
            if let fingerprint = FileFingerprint(url: fileURL) {
                fileFingerprints[fileURL.path] = fingerprint
            }
        }

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
            // Include .delete and .rename to handle atomic save (editors save to temp then rename)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .delete, .rename],
                queue: queue
            )

            source.setEventHandler { [weak self] in
                guard let self = self else { return }
                let event = source.data

                // If file was deleted or renamed (atomic save), re-establish watch
                if event.contains(.delete) || event.contains(.rename) {
                    self.handleFileReplaced(fileURL: fileURL, oldSource: source, oldFd: fd)
                } else {
                    self.handleFileChange(fileURL: fileURL)
                }
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

    /// Handle file being replaced (atomic save: delete/rename)
    /// Re-establishes the watch on the new file
    private func handleFileReplaced(fileURL: URL, oldSource: DispatchSourceFileSystemObject, oldFd: Int32) {
        // Cancel old source (this will close the old fd via setCancelHandler)
        oldSource.cancel()

        // Remove old source and fd from tracking
        if let sourceIndex = sources.firstIndex(where: { $0 === oldSource }) {
            sources.remove(at: sourceIndex)
        }
        if let fdIndex = fileDescriptors.firstIndex(of: oldFd) {
            fileDescriptors.remove(at: fdIndex)
        }

        // Wait for the editor to complete the atomic rename
        // Use 0.3s delay to handle slow editors or network drives
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }

            let path = fileURL.path

            // Re-open file descriptor for the new file
            let newFd = open(path, O_EVTONLY)
            guard newFd >= 0 else {
                print("ERROR: Failed to re-open file for watching after replace: \(path)")
                // Still trigger the callback since the file did change
                self.handleFileChange(fileURL: fileURL)
                return
            }

            self.fileDescriptors.append(newFd)

            // Create new dispatch source
            let newSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: newFd,
                eventMask: [.write, .extend, .attrib, .delete, .rename],
                queue: self.queue
            )

            newSource.setEventHandler { [weak self] in
                guard let self = self else { return }
                let event = newSource.data
                if event.contains(.delete) || event.contains(.rename) {
                    self.handleFileReplaced(fileURL: fileURL, oldSource: newSource, oldFd: newFd)
                } else {
                    self.handleFileChange(fileURL: fileURL)
                }
            }

            newSource.setCancelHandler {
                close(newFd)
            }

            newSource.resume()
            self.sources.append(newSource)

            // Trigger the change callback (fingerprint comparison happens there)
            self.handleFileChange(fileURL: fileURL)
        }
    }

    /// Handle file change event - only triggers callback if file metadata changed
    private func handleFileChange(fileURL: URL) {
        // Ignore events while paused
        if isPaused {
            return
        }

        let path = fileURL.path

        // Debounce: check if we've triggered recently for this file
        if let lastTime = lastCallbackTime[path],
           Date().timeIntervalSince(lastTime) < debounceInterval {
            return
        }

        // Get new fingerprint with retry logic
        // Sometimes the file isn't fully written yet after an atomic save
        var newFingerprint: FileFingerprint?
        var retryCount = 0
        let maxRetries = 3
        let retryDelay: useconds_t = 50_000 // 50ms

        while newFingerprint == nil && retryCount < maxRetries {
            newFingerprint = FileFingerprint(url: fileURL)
            if newFingerprint == nil {
                retryCount += 1
                if retryCount < maxRetries {
                    usleep(retryDelay)
                }
            }
        }

        guard let fingerprint = newFingerprint else {
            print("FileWatcher: Could not read file metadata: \(fileURL.lastPathComponent)")
            return
        }

        // Check if fingerprint changed
        let oldFingerprint = fileFingerprints[path]
        if oldFingerprint == fingerprint {
            return
        }

        // Update stored fingerprint
        fileFingerprints[path] = fingerprint

        // Update last callback time for debounce
        lastCallbackTime[path] = Date()

        print("File changed: \(fileURL.lastPathComponent)")
        callback?(fileURL)
    }

    /// Stop watching all files
    func stop() {
        queue.sync { stopOnQueue() }
    }

    private func stopOnQueue() {
        // Cancel all dispatch sources
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        fileDescriptors.removeAll()
        fileFingerprints.removeAll()
        lastCallbackTime.removeAll()
    }

    deinit {
        // Directly, not through the queue. Nothing else can hold a reference at
        // this point, so there is no one to race with — and a `queue.sync` here
        // would deadlock if the last reference happened to be released on that
        // queue, which an event handler capturing self can arrange.
        stopOnQueue()
    }
}
