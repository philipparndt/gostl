# gostl - GPU-Accelerated STL & OpenSCAD Viewer

A powerful, modern Go application for inspecting, measuring, and visualizing STL and OpenSCAD files with GPU acceleration. Perfect for 3D printing, CAD analysis, and quality control.

## Features

- **Dual Format Support**:
  - STL files (both ASCII and Binary)
  - OpenSCAD files (.scad) with on-the-fly rendering
  - Automatic file watching and hot-reload
  - Dependency tracking for OpenSCAD imports/uses

- **GPU-Accelerated 3D Visualization**:
  - Interactive 3D model rendering with Raylib
  - Smooth rotation, zoom, and pan with mouse controls
  - Wireframe and filled display modes
  - Camera presets (Top, Bottom, Front, Back, Left, Right)

- **Precision Measurement Tools**:
  - Click to select vertices for measurement
  - Line measurements with live preview
  - Radius measurements (3-point arc)
  - Axis-constrained measurements (X, Y, Z keys)
  - Real-time distance display

- **Comprehensive Analysis**:
  - Model dimensions and bounding box
  - Surface area calculations
  - Mesh volume calculation
  - PLA weight estimates (100% and 15% infill)
  - Triangle and edge statistics

- **Auto-Reload**: Automatically detects file changes and reloads while preserving camera position

## Installation

### Prerequisites

- Go 1.21 or higher
- OpenSCAD (for .scad file support)
- Raylib dependencies (handled automatically by raylib-go)

### From Source

```bash
git clone https://github.com/philipparndt/gostl.git
cd gostl
make build
```

## Usage

### Launch the Viewer

```bash
# Open with file dialog
./gostl-raylib

# Open a specific STL file
./gostl-raylib model.stl

# Open an OpenSCAD file (auto-renders to STL)
./gostl-raylib model.scad
```

### Controls

**Camera:**
- **Left Mouse Drag**: Rotate the model
- **Scroll**: Zoom in/out
- **Middle Mouse Drag**: Pan the view
- **Home**: Reset camera view
- **T/B**: Top/Bottom view
- **1/2**: Front/Back view
- **3/4**: Left/Right view

**Display:**
- **W**: Toggle wireframe mode
- **F**: Toggle filled mode

**Measurement:**
- **Left Click**: Select vertices for measurement
  - First click: Select start point (red)
  - Second click: Select end point (green) and measure
- **X, Y, Z**: Constrain measurement to axis (press again to toggle off)
- **R**: Toggle radius measurement mode (3-point arc)
- **ESC**: Clear selection

**Live Preview:**
- Distance preview appears in bottom-right while drawing measurements
- Shows axis delta (ΔX, ΔY, ΔZ) when axis-constrained
- Works across all keyboard layouts (QWERTY, QWERTZ, etc.)

### Model Information Display

The left panel shows:
- **Dimensions**: Model name, triangle count, surface area, volume, size
- **PLA Weight**: Estimated weights at 100% and 15% infill
- **Measure**: Active measurement details (when points selected)
- **View**: Camera preset shortcuts
- **Navigate**: Control reference
- **Constraints**: Axis constraint status (when measuring)

### OpenSCAD Support

When opening a `.scad` file:
- Automatically renders to STL using OpenSCAD CLI
- Monitors the source file and all dependencies (use/include)
- Auto-reloads on any file change
- Shows loading indicator during re-render
- Preserves camera position across reloads

## Make Targets

```bash
make help          # Show all available targets
make build         # Build the binary
make run           # Build and run with example STL file
make run-scad      # Build and run with example OpenSCAD file
make test          # Run tests
make clean         # Clean build artifacts
make install       # Install to $GOPATH/bin
```

## Architecture

```
gostl/
├── cmd/gostl-raylib/   # Main Raylib application
│   └── main.go         # Entry point and UI
├── pkg/
│   ├── geometry/       # 3D geometry types and operations
│   ├── stl/            # STL model and parsing
│   ├── analysis/       # Measurement and analysis tools
│   ├── openscad/       # OpenSCAD rendering and dependency resolution
│   ├── watcher/        # File watching with debouncing
│   └── viewer/         # (legacy) Fyne renderer
└── go.mod
```

### Key Design Decisions

1. **GPU Acceleration**: Uses Raylib for hardware-accelerated 3D rendering
2. **Thread Safety**: Background file loading with main-thread mesh creation
3. **Keyboard Layout Independence**: Uses character input (GetCharPressed) instead of physical keys
4. **Hot Reload**: Debounced file watching (500ms) for smooth auto-updates
5. **Modular Architecture**: Clean separation between rendering, parsing, and analysis

## Examples

### STL File Analysis
```bash
./gostl-raylib examples/h2d-named/Large_Insert_13_6.stl
```

### OpenSCAD Development Workflow
```bash
# Open your OpenSCAD project
./gostl-raylib ~/projects/my-model.scad

# Edit the file in your favorite editor
# Viewer automatically reloads on save
```

## Development

### Running Tests
```bash
make test
```

### Code Coverage
```bash
make test-coverage
```

### Format Code
```bash
make fmt
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License - see LICENSE file for details

## Author

Philipp Arndt (@philipparndt)
