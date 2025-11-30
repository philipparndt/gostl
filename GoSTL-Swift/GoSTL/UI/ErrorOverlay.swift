import SwiftUI

/// Error overlay panel that displays at the bottom of the screen
/// Similar to React's development error overlay
struct ErrorOverlay: View {
    let error: OpenSCADError
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenSCAD Error")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("The file will auto-reload when the error is fixed")
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
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

                        case .renderFailed(let message):
                            Text("Render Failed")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text(message)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                        case .emptyFile:
                            Text("Empty File")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text("The OpenSCAD file produces no geometry.")
                                .font(.body)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
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
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)

        ErrorOverlay(
            error: .renderFailed("ERROR: Parser error: syntax error in file included-file.scad, line 42\nERROR: Cannot continue"),
            onDismiss: {}
        )
    }
    .frame(width: 800, height: 600)
}
