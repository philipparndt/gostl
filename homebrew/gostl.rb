class Gostl < Formula
  desc "3D STL viewer and OpenSCAD renderer"
  homepage "https://github.com/philipparndt/gostl"
  version "0.12.1"
  license "Apache-2.0"

  depends_on arch: :arm64
  depends_on :macos

  url "https://github.com/philipparndt/gostl/releases/download/v0.12.1/GoSTL_darwin_arm64.tar.gz"
  sha256 "c6c2bebb8e7eef7b7946d40161b3e82be0f21c3cb9f506259ed6e8366b324145"

  def install
    # Install CLI binary
    bin.install "GoSTL" => "gostl"
    # Install resource bundle alongside the binary (required for Metal shaders)
    bin.install "GoSTL_GoSTL.bundle"

    # Create app bundle for Finder integration
    app_contents = prefix/"GoSTL.app/Contents"
    app_macos = app_contents/"MacOS"
    app_resources = app_contents/"Resources"

    app_macos.mkpath
    app_resources.mkpath

    # Copy binary to app bundle
    cp bin/"gostl", app_macos/"GoSTL"

    # Copy resource bundle inside app bundle at root level (required by Swift's Bundle.module)
    # The bundle accessor looks at mainBundle.bundlePath/GoSTL_GoSTL.bundle
    cp_r bin/"GoSTL_GoSTL.bundle", prefix/"GoSTL.app/GoSTL_GoSTL.bundle"

    # Create Info.plist with document type declarations
    (app_contents/"Info.plist").write <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
       "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleExecutable</key>
        <string>GoSTL</string>

        <key>CFBundleIdentifier</key>
        <string>com.gostl.viewer</string>

        <key>CFBundleName</key>
        <string>GoSTL</string>

        <key>CFBundleDisplayName</key>
        <string>GoSTL</string>

        <key>CFBundlePackageType</key>
        <string>APPL</string>

        <key>CFBundleVersion</key>
        <string>#{version}</string>

        <key>CFBundleShortVersionString</key>
        <string>#{version}</string>

        <key>LSMinimumSystemVersion</key>
        <string>13.0</string>

        <key>NSHighResolutionCapable</key>
        <true/>

        <key>CFBundleDocumentTypes</key>
        <array>
          <dict>
            <key>CFBundleTypeName</key>
            <string>STL File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>CFBundleTypeExtensions</key>
            <array>
              <string>stl</string>
              <string>STL</string>
            </array>
            <key>LSItemContentTypes</key>
            <array>
              <string>public.standard-tesselated-geometry-format</string>
            </array>
          </dict>
          <dict>
            <key>CFBundleTypeName</key>
            <string>3MF File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>CFBundleTypeExtensions</key>
            <array>
              <string>3mf</string>
              <string>3MF</string>
            </array>
          </dict>
          <dict>
            <key>CFBundleTypeName</key>
            <string>OpenSCAD File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>CFBundleTypeExtensions</key>
            <array>
              <string>scad</string>
            </array>
          </dict>
          <dict>
            <key>CFBundleTypeName</key>
            <string>YAML File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
              <string>yaml</string>
              <string>yml</string>
            </array>
          </dict>
        </array>
      </dict>
      </plist>
    XML
  end

  def post_install
    # Create symlink in HOMEBREW_PREFIX/bin so bundle is found when running via symlink
    bundle_link = HOMEBREW_PREFIX/"bin/GoSTL_GoSTL.bundle"
    bundle_link.unlink if bundle_link.symlink?
    bundle_link.make_symlink(opt_bin/"GoSTL_GoSTL.bundle")

    # Link app bundle to ~/Applications for easy access
    user_apps = Pathname.new(ENV["HOME"])/"Applications"
    user_apps.mkpath unless user_apps.directory?
    app_link = user_apps/"GoSTL.app"

    if app_link.symlink?
      app_link.unlink
    elsif app_link.exist?
      # Don't overwrite user's custom app bundle
      opoo "#{app_link} already exists, skipping link creation. Remove it manually to use the Homebrew version."
    end

    unless app_link.exist?
      app_link.make_symlink(opt_prefix/"GoSTL.app")
    end

    # Register app with Launch Services
    system "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", "-f", opt_prefix/"GoSTL.app"
  end

  def caveats
    <<~EOS
      GoSTL.app has been linked to ~/Applications/GoSTL.app

      You can now:
      - Double-click STL/3MF/SCAD files in Finder to open them with GoSTL
      - Right-click a file and select "Open With" > "GoSTL"
      - Set GoSTL as the default app for STL files in Finder's "Get Info"

      The command-line tool is available as `gostl`.
    EOS
  end

  test do
    # Just verify the binary and bundle exist (GUI app can't be tested in CI)
    assert_predicate bin/"gostl", :exist?
    assert_predicate bin/"GoSTL_GoSTL.bundle/Contents/Resources/default.metallib", :exist?
    assert_predicate prefix/"GoSTL.app/Contents/MacOS/GoSTL", :exist?
  end
end
