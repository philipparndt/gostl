import SwiftUI

/// Overlay that displays model information
struct ModelInfoOverlay: View {
    let modelInfo: ModelInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            Text(modelInfo.fileName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.vertical, 2)

            // Triangle count
            InfoRow_Legacy(label: "Triangles:", value: ModelInfo.formatCount(modelInfo.triangleCount))

            // Dimensions
            InfoRow_Legacy(label: "W:", value: ModelInfo.formatDimension(modelInfo.width))
            InfoRow_Legacy(label: "H:", value: ModelInfo.formatDimension(modelInfo.height))
            InfoRow_Legacy(label: "D:", value: ModelInfo.formatDimension(modelInfo.depth))

            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.vertical, 2)

            // Volume and surface area
            InfoRow_Legacy(label: "Volume:", value: ModelInfo.formatVolume(modelInfo.volume))
            InfoRow_Legacy(label: "Area:", value: ModelInfo.formatArea(modelInfo.surfaceArea))

            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.vertical, 2)

            // Material and weight
            HStack(spacing: 4) {
                Text("Material:")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
                Text(modelInfo.material.rawValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                KeyHint_Legacy(key: "m")
            }
            InfoRow_Legacy(label: "Weight:", value: Material.formatWeight(modelInfo.weight))

            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.vertical, 2)

            // Center position
            VStack(alignment: .leading, spacing: 2) {
                Text("Center:")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
                Text(String(format: "%.1f, %.1f, %.1f",
                           modelInfo.center.x, modelInfo.center.y, modelInfo.center.z))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
            }

            // Help text
            HStack(spacing: 4) {
                KeyHint_Legacy(key: "i")
                Text("to toggle")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.top, 4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.7))
                .shadow(radius: 5)
        )
        .fixedSize()
        .padding(12)
    }
}

/// A single row of information (legacy - kept for preview)
private struct InfoRow_Legacy: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.8))
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

/// A small keyboard key hint badge (legacy - kept for preview)
private struct KeyHint_Legacy: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
            )
    }
}

#Preview {
    let model = STLModel(
        triangles: [
            Triangle(
                v1: Vector3(0, 0, 0),
                v2: Vector3(10, 0, 0),
                v3: Vector3(5, 10, 0)
            )
        ],
        name: "test-model"
    )

    let info = ModelInfo(fileName: "test-model.stl", model: model)

    ZStack {
        Color.gray
        ModelInfoOverlay(modelInfo: info)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
