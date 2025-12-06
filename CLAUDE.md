# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build debug version (includes Metal shader compilation)
make build

# Build release version
make release

# Run debug with a file
make run FILE=./examples/cube.stl

# Run tests
make test

# Clean build artifacts
rm -rf GoSTL-Swift/.build
```

### Running Tests

```bash
cd GoSTL-Swift && swift test

# Run a specific test
cd GoSTL-Swift && swift test --filter STLParserTests
```

## Architecture

GoSTL is a macOS STL/3MF/OpenSCAD viewer built with Swift, SwiftUI, and Metal. The main application is in `GoSTL-Swift/`.

### Key Components

**App Layer** (`GoSTL/App/`)
- `GoSTLApp.swift` - SwiftUI app entry point, menu commands, window management
- `AppState.swift` - Central observable state: model data, camera, rendering options, file watching
- `ContentView.swift` - Main UI layout combining MetalView with SwiftUI overlays

**Rendering Pipeline** (`GoSTL/Rendering/`)
- `MetalRenderer.swift` - Metal render pipelines (mesh, wireframe, grid, measurements, orientation cube)
- `MetalView.swift` - MTKView wrapper for SwiftUI integration
- `Shaders.metal` - Metal shader code (compiled during build via Makefile)
- Data classes (`MeshData`, `WireframeData`, `GridData`, etc.) - GPU buffer management

**Model Parsing** (`GoSTL/Model/`)
- `STLParser.swift` - Binary and ASCII STL parsing
- `ThreeMFParser.swift` - 3MF file parsing with multi-plate support
- `STLModel.swift` - Triangle mesh representation, edge extraction, bounding box

**Interactive Features**
- `GoSTL/Measurement/` - Distance, angle, and radius measurement tools
- `GoSTL/Slicing/` - Model slicing/clipping along axes
- `GoSTL/Camera/` - Orbital camera with preset views
- `GoSTL/Input/` - Mouse/keyboard input handling, ray casting for vertex picking

**External Tool Integration**
- `GoSTL/OpenSCAD/` - Renders .scad files via OpenSCAD CLI
- `GoSTL/Go3mf/` - YAML config for go3mf tool integration
- `GoSTL/FileWatcher/` - FSEvents-based file watching for hot reload

### Rendering Architecture

The app uses a multi-pass Metal rendering pipeline:
1. Build plate (transparent background)
2. Grid lines (alpha blended)
3. Slice planes (when slicing active)
4. Main mesh (lit with material properties)
5. Wireframe (instanced cylinders for edges)
6. Cut edges (colored by axis when slicing)
7. Measurements (lines, points, circles)
8. Grid labels (text billboards)
9. Orientation cube (separate viewport, top-right)

### State Management

`AppState` is the central @Observable class containing:
- Current model and cached mesh/wireframe data
- Camera state (position, angles, target)
- Display modes (wireframe, grid, build plate)
- Measurement system state
- File watching and reload state

UI updates trigger through SwiftUI observation. Menu commands communicate via NotificationCenter.

## File Types Supported

- `.stl` - Binary and ASCII STL files
- `.3mf` - 3D Manufacturing Format (multi-plate support)
- `.scad` - OpenSCAD files (rendered via CLI)
- `.yaml/.yml` - go3mf configuration files

## Feature Documentation

**IMPORTANT:** When adding or modifying features, always update the corresponding Gherkin feature files in `features/`.

These `.feature` files serve as living documentation and describe all application behavior in Cucumber/Gherkin format. When implementing changes:

1. **New feature** → Create a new `features/<feature_name>.feature` file
2. **Modified behavior** → Update the relevant existing `.feature` file
3. **New keyboard shortcut** → Add to `features/keyboard_shortcuts.feature` and `features/README.md`
4. **New menu item** → Add to `features/menus.feature`

Feature files use tags like `@camera`, `@measurement`, `@slicing`, `@visualization` for categorization. See `features/README.md` for the full tag list and file organization.
