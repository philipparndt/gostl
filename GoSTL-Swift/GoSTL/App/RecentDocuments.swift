import Foundation

/// Manages recently opened documents
@Observable
final class RecentDocuments: @unchecked Sendable {
    static let shared = RecentDocuments()

    private let maxRecentItems = 10
    private let configDir: URL
    private let configFile: URL

    var recentURLs: [URL] = []

    private init() {
        // Set up config directory: ~/.config/gostl
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        configDir = homeDir.appendingPathComponent(".config").appendingPathComponent("gostl")
        configFile = configDir.appendingPathComponent("recent.json")

        // Create config directory if needed
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        loadRecentDocuments()
    }

    /// Add a document to recent items
    func addDocument(_ url: URL) {
        // Remove if already exists (to move to top)
        recentURLs.removeAll { $0 == url }

        // Add to beginning
        recentURLs.insert(url, at: 0)

        // Limit to max items
        if recentURLs.count > maxRecentItems {
            recentURLs = Array(recentURLs.prefix(maxRecentItems))
        }

        saveRecentDocuments()
    }

    /// Clear all recent documents
    func clearRecents() {
        recentURLs = []
        saveRecentDocuments()
    }

    /// Remove a specific document from recents
    func removeDocument(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        saveRecentDocuments()
    }

    // MARK: - Persistence

    private struct RecentDocumentsConfig: Codable {
        let recentFiles: [String]
    }

    private func saveRecentDocuments() {
        let config = RecentDocumentsConfig(recentFiles: recentURLs.map { $0.path })

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: configFile)
        } catch {
            print("ERROR: Failed to save recent documents: \(error)")
        }
    }

    private func loadRecentDocuments() {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: configFile)
            let decoder = JSONDecoder()
            let config = try decoder.decode(RecentDocumentsConfig.self, from: data)

            // Convert paths to URLs and filter out non-existent files
            recentURLs = config.recentFiles
                .map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }

            // If some files were removed, save the cleaned list
            if recentURLs.count != config.recentFiles.count {
                saveRecentDocuments()
            }
        } catch {
            print("ERROR: Failed to load recent documents: \(error)")
        }
    }
}
