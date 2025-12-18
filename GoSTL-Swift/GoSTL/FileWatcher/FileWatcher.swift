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
class FileWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private let queue = DispatchQueue(label: "com.gostl.filewatcher")
    private var callback: ((URL) -> Void)?
    private var fileFingerprints: [String: FileFingerprint] = [:]

    /// Whether the watcher is paused (ignores events)
    var isPaused: Bool = false

    init() {}

    /// Start watching files for changes
    /// - Parameters:
    ///   - files: Array of file URLs to watch
    ///   - callback: Closure to call when a file changes (receives the changed file URL)
    /// - Throws: Error if watching cannot be set up
    func watch(files: [URL], callback: @escaping (URL) -> Void) throws {
        // Stop any existing watching
        stop()

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

        // Wait briefly for the editor to complete the atomic rename
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
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

        // Get new fingerprint
        guard let newFingerprint = FileFingerprint(url: fileURL) else {
            print("Could not read file metadata: \(fileURL.lastPathComponent)")
            return
        }

        // Check if fingerprint changed
        let oldFingerprint = fileFingerprints[path]
        if oldFingerprint == newFingerprint {
            return
        }

        // Update stored fingerprint
        fileFingerprints[path] = newFingerprint

        print("File changed: \(fileURL.lastPathComponent)")
        callback?(fileURL)
    }

    /// Stop watching all files
    func stop() {
        // Cancel all dispatch sources
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        fileDescriptors.removeAll()
        fileFingerprints.removeAll()
    }

    deinit {
        stop()
    }
}
