import SwiftUI

/// Panel showing OpenSCAD warnings in the bottom-right corner
struct WarningsPanel: View {
    let warnings: [String]
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // Collapsed header - always visible
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))

                    Text("\(warnings.count) warning\(warnings.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { index, warning in
                        WarningRow(warning: warning)
                    }
                }
                .padding(8)
                .frame(maxWidth: 400, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

/// Single warning row
private struct WarningRow: View {
    let warning: String

    private var warningType: WarningType {
        if warning.hasPrefix("WARNING:") {
            return .warning
        } else if warning.hasPrefix("DEPRECATED:") {
            return .deprecated
        } else {
            return .other
        }
    }

    private var displayText: String {
        // Remove the prefix for cleaner display
        if warning.hasPrefix("WARNING: ") {
            return String(warning.dropFirst(9))
        } else if warning.hasPrefix("DEPRECATED: ") {
            return String(warning.dropFirst(12))
        }
        return warning
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Icon based on type
            Image(systemName: warningType.icon)
                .foregroundColor(warningType.color)
                .font(.system(size: 10))
                .frame(width: 12)

            // Warning text
            Text(displayText)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private enum WarningType {
        case warning
        case deprecated
        case other

        var icon: String {
            switch self {
            case .warning: return "exclamationmark.triangle"
            case .deprecated: return "clock.arrow.circlepath"
            case .other: return "info.circle"
            }
        }

        var color: Color {
            switch self {
            case .warning: return .orange
            case .deprecated: return .yellow
            case .other: return .gray
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray
        VStack {
            Spacer()
            HStack {
                Spacer()
                WarningsPanel(warnings: [
                    "WARNING: Can't open library './parts.scad'. in file test.scad, line 1",
                    "DEPRECATED: Variable names starting with digits (\"1_HE\") will be removed in future releases. in file esp-rack.scad, line 6",
                    "DEPRECATED: Variable names starting with digits (\"2_HE\") will be removed in future releases. in file esp-rack.scad, line 7"
                ])
                .padding()
            }
        }
    }
    .frame(width: 500, height: 300)
}
