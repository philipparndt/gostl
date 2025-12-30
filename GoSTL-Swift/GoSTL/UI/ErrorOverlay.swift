import SwiftUI
import AppKit

/// A selectable text view that doesn't cause layout shifts
struct SelectableText: NSViewRepresentable {
    let text: String
    let font: NSFont

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = font
        textView.string = text

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        textView.string = text
        textView.font = font
    }
}

/// Unified error type for displaying in the error overlay
enum ToolError {
    case openSCAD(OpenSCADError)
    case go3mf(Go3mfError)

    var title: String {
        switch self {
        case .openSCAD: return "OpenSCAD Error"
        case .go3mf: return "go3mf Error"
        }
    }

    var subtitle: String {
        switch self {
        case .openSCAD: return "The file will auto-reload when the error is fixed"
        case .go3mf: return "Build failed"
        }
    }
}

/// Error overlay panel that displays at the bottom of the screen
/// Similar to React's development error overlay
struct ErrorOverlay: View {
    let error: ToolError
    let onDismiss: () -> Void
    @State private var eventMonitor: Any?

    var body: some View {
        VStack {
            // Invisible layer to capture clicks
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    // Don't dismiss on background tap, just capture the event
                }

            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.title)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(error.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // Error message
                VStack(alignment: .leading, spacing: 8) {
                    switch error {
                    case .openSCAD(let openSCADError):
                        openSCADErrorContent(openSCADError)

                    case .go3mf(let go3mfError):
                        go3mfErrorContent(go3mfError)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 300, alignment: .topLeading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: -5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.3), lineWidth: 2)
            )
            .padding(20)
        }
        .onAppear {
            // Set up local event monitor for escape key
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // Escape key
                    onDismiss()
                    return nil // Consume the event
                }
                return event
            }
        }
        .onDisappear {
            // Clean up event monitor
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }

    @ViewBuilder
    private func openSCADErrorContent(_ error: OpenSCADError) -> some View {
        switch error {
        case .openSCADNotFound:
            Text("OpenSCAD Not Installed")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("OpenSCAD is required to render .scad files.")
                .font(.body)

            VStack(alignment: .leading, spacing: 4) {
                Text("Install via Homebrew:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("brew install --cask openscad")
                    .font(.system(.caption, design: .monospaced))
                    .padding(6)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Or download from:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Link("https://openscad.org/downloads.html",
                     destination: URL(string: "https://openscad.org/downloads.html")!)
                    .font(.caption)
            }
            .padding(.top, 4)

        case .renderFailed(let message, _):
            Text("Render Failed")
                .font(.subheadline)
                .fontWeight(.semibold)

            SelectableText(
                text: message,
                font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            )
            .frame(maxWidth: .infinity, alignment: .leading)

        case .emptyFile:
            Text("Empty File")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("The OpenSCAD file produces no geometry.")
                .font(.body)
        }
    }

    @ViewBuilder
    private func go3mfErrorContent(_ error: Go3mfError) -> some View {
        switch error {
        case .go3mfNotFound:
            Text("go3mf Not Installed")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("go3mf is required to process configuration files.")
                .font(.body)

            VStack(alignment: .leading, spacing: 4) {
                Text("Install from:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Link("https://github.com/parndt/go3mf",
                     destination: URL(string: "https://github.com/parndt/go3mf")!)
                    .font(.caption)
            }
            .padding(.top, 4)

        case .buildFailed(let message):
            Text("Build Failed")
                .font(.subheadline)
                .fontWeight(.semibold)

            SelectableText(
                text: message,
                font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("OpenSCAD Error") {
    ZStack {
        Color.gray.opacity(0.3)

        ErrorOverlay(
            error: .openSCAD(.renderFailed("ERROR: Parser error: syntax error in file included-file.scad, line 42\nERROR: Cannot continue", messages: [])),
            onDismiss: {}
        )
    }
    .frame(width: 800, height: 600)
}

#Preview("go3mf Error") {
    ZStack {
        Color.gray.opacity(0.3)

        ErrorOverlay(
            error: .go3mf(.buildFailed("Failed to build project.yaml\nError: cannot find file 'model.stl'")),
            onDismiss: {}
        )
    }
    .frame(width: 800, height: 600)
}
