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
            InfoRow(label: "Triangles:", value: ModelInfo.formatCount(modelInfo.triangleCount))

            // Dimensions
            InfoRow(label: "W:", value: ModelInfo.formatDimension(modelInfo.width))
            InfoRow(label: "H:", value: ModelInfo.formatDimension(modelInfo.height))
            InfoRow(label: "D:", value: ModelInfo.formatDimension(modelInfo.depth))

            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.vertical, 2)

            // Volume and surface area
            InfoRow(label: "Volume:", value: ModelInfo.formatVolume(modelInfo.volume))
            InfoRow(label: "Area:", value: ModelInfo.formatArea(modelInfo.surfaceArea))

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
            Text("Press 'i' to toggle")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.5))
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

/// A single row of information
private struct InfoRow: View {
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
