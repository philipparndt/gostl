import SwiftUI

/// Message severity levels for OpenSCAD output
private enum MessageType: Int, Comparable {
    case other = 0
    case echo = 1
    case deprecated = 2
    case warning = 3

    static func < (lhs: MessageType, rhs: MessageType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func from(_ message: String) -> MessageType {
        if message.hasPrefix("WARNING:") {
            return .warning
        } else if message.hasPrefix("DEPRECATED:") {
            return .deprecated
        } else if message.hasPrefix("ECHO:") {
            return .echo
        } else {
            return .other
        }
    }

    var icon: String {
        switch self {
        case .warning: return "exclamationmark.triangle"
        case .deprecated: return "clock.arrow.circlepath"
        case .echo: return "text.bubble"
        case .other: return "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .warning: return .orange
        case .deprecated: return .yellow
        case .echo: return .cyan
        case .other: return .gray
        }
    }
}

/// Panel showing OpenSCAD messages in the bottom-right corner
struct WarningsPanel: View {
    let warnings: [String]
    @State private var isExpanded: Bool = false

    /// Determine the highest severity message type
    private var highestSeverity: MessageType {
        warnings.map { MessageType.from($0) }.max() ?? .other
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: highestSeverity.icon + ".fill")
                        .foregroundColor(highestSeverity.color)
                        .font(.system(size: 12))

                    Text("\(warnings.count) message\(warnings.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)

                    if isExpanded {
                        Spacer()
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: isExpanded ? .infinity : nil)
                .background(highestSeverity.color.opacity(0.3))
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                // Separator line
                Rectangle()
                    .fill(highestSeverity.color.opacity(0.4))
                    .frame(height: 1)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { index, warning in
                        WarningRow(warning: warning)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: isExpanded ? 400 : nil)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(highestSeverity.color.opacity(0.5), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Single warning row
private struct WarningRow: View {
    let warning: String

    private var messageType: MessageType {
        MessageType.from(warning)
    }

    private var displayText: String {
        // Remove the prefix for cleaner display
        if warning.hasPrefix("WARNING: ") {
            return String(warning.dropFirst(9))
        } else if warning.hasPrefix("DEPRECATED: ") {
            return String(warning.dropFirst(12))
        } else if warning.hasPrefix("ECHO: ") {
            return String(warning.dropFirst(6))
        }
        return warning
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Icon based on type
            Image(systemName: messageType.icon)
                .foregroundColor(messageType.color)
                .font(.system(size: 10))
                .frame(width: 12)

            // Warning text
            Text(displayText)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

#Preview("Mixed messages") {
    ZStack {
        Color.gray
        VStack {
            Spacer()
            HStack {
                Spacer()
                WarningsPanel(warnings: [
                    "WARNING: Can't open library './parts.scad'. in file test.scad, line 1",
                    "DEPRECATED: Variable names starting with digits (\"1_HE\") will be removed in future releases. in file esp-rack.scad, line 6",
                    "ECHO: -53.6289",
                    "ECHO: \"Hello from OpenSCAD\""
                ])
                .padding()
            }
        }
    }
    .frame(width: 500, height: 300)
}

#Preview("Echo only") {
    ZStack {
        Color.gray
        VStack {
            Spacer()
            HStack {
                Spacer()
                WarningsPanel(warnings: [
                    "ECHO: -53.6289",
                    "ECHO: \"Hello from OpenSCAD\"",
                    "ECHO: [1, 2, 3]"
                ])
                .padding()
            }
        }
    }
    .frame(width: 500, height: 300)
}
