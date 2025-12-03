import Foundation
import Yams

/// Configuration for a go3mf YAML file
struct Go3mfConfig: Codable {
    let output: String?
    let packingDistance: Double?
    let packingAlgorithm: String?
    let objects: [Go3mfObject]

    enum CodingKeys: String, CodingKey {
        case output
        case packingDistance = "packing_distance"
        case packingAlgorithm = "packing_algorithm"
        case objects
    }
}

/// An object in the go3mf configuration
struct Go3mfObject: Codable {
    let name: String
    let normalizePosition: Bool?
    let config: [[String: String]]?
    let parts: [Go3mfPart]

    enum CodingKeys: String, CodingKey {
        case name
        case normalizePosition = "normalize_position"
        case config
        case parts
    }
}

/// A part within an object
struct Go3mfPart: Codable {
    let name: String
    let file: String
    let filament: Int?
    let rotationX: Double?
    let rotationY: Double?
    let rotationZ: Double?
    let positionX: Double?
    let positionY: Double?
    let positionZ: Double?
    let config: [[String: String]]?

    enum CodingKeys: String, CodingKey {
        case name
        case file
        case filament
        case rotationX = "rotation_x"
        case rotationY = "rotation_y"
        case rotationZ = "rotation_z"
        case positionX = "position_x"
        case positionY = "position_y"
        case positionZ = "position_z"
        case config
    }
}

/// Parser for go3mf YAML configuration files
enum Go3mfConfigParser {
    /// Parse a YAML configuration file
    static func parse(url: URL) throws -> Go3mfConfig {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(yaml: content)
    }

    /// Parse YAML content string
    static func parse(yaml content: String) throws -> Go3mfConfig {
        let decoder = YAMLDecoder()
        return try decoder.decode(Go3mfConfig.self, from: content)
    }
}

/// Errors during go3mf configuration parsing
enum Go3mfConfigError: LocalizedError {
    case invalidYaml(String)
    case missingFile(String)
    case unsupportedFileType(String)
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidYaml(let message):
            return "Invalid YAML configuration: \(message)"
        case .missingFile(let path):
            return "File not found: \(path)"
        case .unsupportedFileType(let ext):
            return "Unsupported file type: \(ext)"
        case .renderFailed(let message):
            return "Render failed: \(message)"
        }
    }
}
