import SwiftUI

/// Overlay that displays the selection rectangle and selection count
struct SelectionRectangleOverlay: View {
    let measurementSystem: MeasurementSystem

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Draw selection rectangle
                if let rect = measurementSystem.selectionRect {
                    // The selection rect is stored in drawable coordinates (pixels)
                    // We need to scale it to SwiftUI view coordinates (points)
                    // For Retina displays, drawable is typically 2x the view size
                    SelectionRectangle(
                        start: rect.start,
                        end: rect.end,
                        viewSize: geometry.size
                    )
                }

                // Show selection count when items are selected
                if !measurementSystem.selectedMeasurements.isEmpty && measurementSystem.selectionRect == nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            SelectionInfoBadge(count: measurementSystem.selectedMeasurements.count)
                                .padding(20)
                        }
                    }
                }
            }
        }
    }
}

/// The selection rectangle shape
struct SelectionRectangle: View {
    let start: CGPoint
    let end: CGPoint
    let viewSize: CGSize

    var body: some View {
        // Scale factor: drawable coordinates to view coordinates
        // On Retina, drawable is typically 2x view size
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        let scaledStart = CGPoint(x: start.x / scale, y: start.y / scale)
        let scaledEnd = CGPoint(x: end.x / scale, y: end.y / scale)

        let minX = min(scaledStart.x, scaledEnd.x)
        let minY = min(scaledStart.y, scaledEnd.y)
        let width = abs(scaledEnd.x - scaledStart.x)
        let height = abs(scaledEnd.y - scaledStart.y)

        Rectangle()
            .fill(Color.blue.opacity(0.1))
            .overlay(
                Rectangle()
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            )
            .frame(width: width, height: height)
            .position(x: minX + width / 2, y: minY + height / 2)
    }
}

/// Badge showing selection count
struct SelectionInfoBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.blue)

            Text("\(count) selected")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)

            Text("⌫ to delete")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.75))
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
        )
    }
}

#Preview {
    let system = MeasurementSystem()
    system.selectionRect = (start: CGPoint(x: 100, y: 100), end: CGPoint(x: 300, y: 250))

    return ZStack {
        Color.gray
        SelectionRectangleOverlay(measurementSystem: system)
    }
    .frame(width: 500, height: 400)
}
