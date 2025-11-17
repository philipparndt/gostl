# gostl - Modern STL File Inspector

A powerful, modern Go application for inspecting and measuring STL (Stereolithography) files with precision. Perfect for 3D printing, CAD analysis, and quality control.

Available in two interfaces:
- **Desktop GUI** - Interactive 3D viewer with visual point selection and real-time measurements
- **CLI** - Fast command-line tool for scripting and batch processing

## Features

- **Dual Format Support**: Reads both ASCII and Binary STL files automatically
- **Desktop GUI Application**:
  - Interactive 3D model visualization
  - Rotate, zoom, and pan with mouse controls
  - Click to select vertices for measurement
  - Real-time distance measurements (X, Y, Z, and total distance)
  - Visual feedback with color-coded selection markers
  - Model information panel
- **Comprehensive CLI Measurements**:
  - Model dimensions and bounding box
  - Edge length analysis (min, max, average, specific edges)
  - Surface area calculations
  - Point-to-point distance measurements
  - Triangle analysis (area, perimeter, angles)
- **Fast & Efficient**: Written in Go for high performance
- **Modular Architecture**: Clean separation between parsing, geometry, and UI

## Installation

### From Source

```bash
git clone https://github.com/philipparndt/gostl.git
cd gostl

# Build CLI tool
make build

# Build GUI application
make build-gui

# Or build both
make build-all
```

### Using Make

```bash
# Build and install both applications
make install
```

## Usage

### Desktop GUI Application

Launch the GUI application:

```bash
# Open with file dialog
./gostl-gui

# Or open a specific file directly
./gostl-gui examples/cube.stl
```

**GUI Features:**
- **3D Visualization**: See your STL model rendered in 3D with wireframe display
- **Mouse Controls**:
  - **Drag**: Rotate the model around to view from any angle
  - **Scroll**: Zoom in and out
  - **Click**: Select vertices (points) on the model
- **Precise Measurements**:
  - Select any two vertices by clicking on them
  - First point appears in **red**, second point in **green**
  - Get instant measurements:
    - **Distance X**: Horizontal distance between points
    - **Distance Y**: Depth distance between points
    - **Distance Z**: Vertical distance between points
    - **Total Distance**: Straight-line distance in 3D space
- **Model Information**: View triangle count, surface area, and dimensions
- **Clear Selection**: Reset point selection to measure different distances

**Perfect for:**
- Verifying 3D print dimensions
- Measuring specific features on complex models
- Quality control and inspection
- Understanding model geometry visually

### CLI Commands

#### Basic Information

Get comprehensive information about an STL file:

```bash
./gostl info model.stl
```

Output includes:
- Triangle and edge counts
- Bounding box dimensions
- Model dimensions (width, height, depth)
- Surface area
- Edge length statistics

Example output:
```
STL File Information
====================
File: model.stl

Model Statistics:
  Triangles: 1248
  Edges: 3744
  Surface Area: 25834.123456 square units

Bounding Box:
  Min: (-10.000000, -10.000000, 0.000000)
  Max: (10.000000, 10.000000, 5.000000)
  Center: (0.000000, 0.000000, 2.500000)

Dimensions:
  Width (X): 20.000000 units
  Depth (Y): 20.000000 units
  Height (Z): 5.000000 units
  Diagonal: 21.794495 units
  Volume: 2000.000000 cubic units

Edge Lengths:
  Minimum: 0.125000 units
  Maximum: 15.811388 units
  Average: 2.456789 units
```

### Edge Analysis

#### Find Longest Edges

```bash
./gostl edges model.stl --longest -n 10
```

#### Find Shortest Edges

```bash
./gostl edges model.stl --shortest -n 10
```

#### Filter Edges by Length Range

Find all edges between 5 and 10 units:

```bash
./gostl edges model.stl --min 5.0 --max 10.0 -n 20
```

#### List All Edges

```bash
./gostl edges model.stl -n 100
```

Example output:
```
Top 10 Longest Edges
====================
Total edges in model: 3744
Min edge length: 0.125000 units
Max edge length: 15.811388 units
Avg edge length: 2.456789 units

Index  Start                               End                                 Length
-----------------------------------------------------------------------------------------------------------
1      (10.000000, 8.500000, 2.300000)     (10.000000, -7.200000, 2.300000)    15.811388
2      (-9.500000, 10.000000, 1.800000)    (-9.500000, -5.300000, 1.800000)    15.300000
...
```

### Point-to-Point Measurement

Measure the distance between two 3D points:

```bash
./gostl measure model.stl --x1 0 --y1 0 --z1 0 --x2 10 --y2 10 --z2 5
```

The tool will:
- Calculate the direct distance between the points
- Find the nearest vertices in the model to each point
- Calculate the distance between those vertices

Example output:
```
Point-to-Point Measurement
==========================

Point 1: (0.000000, 0.000000, 0.000000)
  Nearest vertex: (0.125000, 0.050000, 0.000000) (distance: 0.134629)

Point 2: (10.000000, 10.000000, 5.000000)
  Nearest vertex: (9.950000, 9.980000, 5.000000) (distance: 0.053852)

Direct distance: 15.000000 units
Distance between nearest vertices: 14.991666 units
```

### Triangle Analysis

#### Find Largest Triangles

```bash
./gostl triangles model.stl --largest -n 5
```

#### Find Smallest Triangles

```bash
./gostl triangles model.stl --smallest -n 5
```

#### List Triangles

```bash
./gostl triangles model.stl -n 10
```

Example output:
```
Top 5 Largest Triangles
====================
Total triangles: 1248
Total surface area: 25834.123456 square units
Min triangle area: 0.015625 square units
Max triangle area: 48.500000 square units
Avg triangle area: 20.698178 square units

Triangle #42:
  Area: 48.500000 square units
  Perimeter: 31.200000 units
  Vertices: (-10.000000, 5.000000, 0.000000), (0.000000, 5.000000, 0.000000), (-5.000000, 15.000000, 0.000000)
...
```

## Command Reference

### Global Flags

- `-h, --help`: Show help for any command
- `-v, --version`: Show version information

### Commands

#### `info [file]`

Display comprehensive information about an STL file.

**Arguments:**
- `file`: Path to the STL file

**Example:**
```bash
./gostl info model.stl
```

#### `edges [file]`

Analyze and measure edges in an STL file.

**Arguments:**
- `file`: Path to the STL file

**Flags:**
- `-n, --count int`: Number of edges to display (default: 10)
- `-l, --longest`: Show longest edges
- `-s, --shortest`: Show shortest edges
- `--min float`: Minimum edge length filter
- `--max float`: Maximum edge length filter

**Examples:**
```bash
./gostl edges model.stl --longest -n 20
./gostl edges model.stl --min 5.0 --max 10.0
```

#### `measure [file]`

Measure distance between two 3D points.

**Arguments:**
- `file`: Path to the STL file

**Flags:**
- `--x1 float`: X coordinate of first point
- `--y1 float`: Y coordinate of first point
- `--z1 float`: Z coordinate of first point
- `--x2 float`: X coordinate of second point
- `--y2 float`: Y coordinate of second point
- `--z2 float`: Z coordinate of second point

All coordinate flags must be provided together.

**Example:**
```bash
./gostl measure model.stl --x1 0 --y1 0 --z1 0 --x2 10 --y2 5 --z2 3
```

#### `triangles [file]`

Analyze triangles in an STL file.

**Arguments:**
- `file`: Path to the STL file

**Flags:**
- `-n, --count int`: Number of triangles to display (default: 10)
- `-l, --largest`: Show largest triangles by area
- `-s, --smallest`: Show smallest triangles by area

**Examples:**
```bash
./gostl triangles model.stl --largest -n 5
./gostl triangles model.stl --smallest -n 10
```

## Architecture

The project is organized into clear, modular packages:

```
gostl/
├── cmd/gostl/          # CLI application
│   ├── main.go         # Entry point
│   ├── info.go         # Info command
│   ├── edges.go        # Edge analysis command
│   ├── measure.go      # Point-to-point measurement
│   └── triangles.go    # Triangle analysis command
├── pkg/
│   ├── geometry/       # 3D geometry types and operations
│   │   ├── vector3.go  # 3D vector math
│   │   ├── triangle.go # Triangle operations
│   │   └── bounds.go   # Bounding box
│   ├── stl/            # STL file parsing
│   │   ├── model.go    # STL model representation
│   │   └── parser.go   # ASCII and Binary parsers
│   └── analysis/       # Measurement and analysis tools
│       └── measurements.go
└── go.mod
```

### Key Design Decisions

1. **Automatic Format Detection**: The parser automatically detects ASCII vs Binary format
2. **Modular Packages**: Clear separation between geometry, parsing, and analysis
3. **Performance**: Efficient algorithms with minimal memory allocations
4. **Extensibility**: Clean interfaces designed for future GUI integration

## Future Enhancements

- **Desktop GUI**: Native desktop application with 3D visualization (using Fyne or Gio)
- **Interactive 3D Viewer**: Rotate, zoom, and select points/edges visually
- **Export Capabilities**: Export measurements to CSV, JSON, or PDF
- **Batch Processing**: Analyze multiple STL files at once
- **Advanced Analysis**:
  - Wall thickness analysis
  - Overhang detection for 3D printing
  - Volume calculations (watertight mesh)
  - Mesh quality analysis

## Development

### Running Tests

```bash
go test ./pkg/... -v
```

### Building

```bash
go build -o gostl ./cmd/gostl
```

### Code Coverage

```bash
go test ./pkg/... -coverprofile=coverage.out
go tool cover -html=coverage.out
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License - see LICENSE file for details

## Author

Philipp Arndt (@philipparndt)
