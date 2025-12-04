import SwiftUI
import Metal

/// Plate selector panel for 3MF files with multiple build plates
/// Displayed at the bottom center of the screen
struct PlateSelector: View {
    let appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            // Plate icon
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))

            // Plate buttons
            ForEach(appState.availablePlates) { plate in
                PlateButton(
                    plate: plate,
                    isSelected: appState.selectedPlateId == plate.id,
                    action: { selectPlate(plate.id) }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
        )
    }

    private func selectPlate(_ plateId: Int) {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        try? appState.selectPlate(plateId, device: device)
    }
}

/// Individual plate button
struct PlateButton: View {
    let plate: ThreeMFPlate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(plate.name)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.purple.opacity(0.5) : Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let appState = AppState()
    // Simulate multiple plates
    appState.threeMFParseResult = ThreeMFParseResult(
        plates: [
            ThreeMFPlate(id: 1, name: "Inserts", objectIds: [1, 2], thumbnailPath: nil),
            ThreeMFPlate(id: 2, name: "Case (H2D Logo)", objectIds: [3, 4], thumbnailPath: nil),
            ThreeMFPlate(id: 3, name: "Case (Bambu Logo)", objectIds: [5, 6], thumbnailPath: nil),
            ThreeMFPlate(id: 4, name: "Latches", objectIds: [7, 8], thumbnailPath: nil),
        ],
        trianglesByPlate: [:],
        allTriangles: [],
        name: "Test"
    )
    appState.selectedPlateId = 1

    return ZStack {
        Color.gray
        VStack {
            Spacer()
            PlateSelector(appState: appState)
                .padding(.bottom, 20)
        }
    }
}
