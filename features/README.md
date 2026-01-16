# GoSTL Feature Specifications

This directory contains Cucumber/Gherkin feature files documenting all functionality of the GoSTL 3D model viewer application. These specifications serve as:

1. **Living documentation** - A complete reference of all features
2. **Reimplementation guide** - Sufficient detail to rebuild the app in any technology
3. **Test specifications** - Can be used by QA teams for manual or automated testing

## Feature Categories

### File Handling
- `file_open.feature` - Opening 3D model files (STL, 3MF, OpenSCAD, go3mf)
- `recent_files.feature` - Recent files management
- `auto_reload.feature` - Auto-reload on file changes

### Camera & Navigation
- `camera_navigation.feature` - Mouse controls for rotation, pan, zoom
- `camera_presets.feature` - Keyboard shortcuts for standard views
- `orientation_cube.feature` - Interactive 3D orientation cube

### Visualization
- `wireframe_display.feature` - Wireframe display modes
- `grid_display.feature` - Reference grid display
- `build_plate.feature` - 3D printer build plate visualization
- `rendering.feature` - 3D rendering quality and features

### Model Interaction
- `slicing.feature` - Model slicing and cross-sections
- `leveling.feature` - Level object by aligning two points
- `measure_distance.feature` - Distance measurement tool
- `measure_angle.feature` - Angle measurement tool
- `measure_radius.feature` - Radius/circle measurement tool
- `measurement_selection.feature` - Selecting and managing measurements

### Model Properties
- `material_system.feature` - Material selection and weight calculation
- `multi_plate_3mf.feature` - 3MF multi-plate support
- `info_panel.feature` - Model information display
- `model_analysis.feature` - Geometric analysis (volume, surface area)

### Application
- `menus.feature` - Menu structure and organization
- `keyboard_shortcuts.feature` - All keyboard shortcuts
- `window_management.feature` - Multi-window and tab support
- `external_tools.feature` - Integration with external tools

### Internal/Technical
- `ray_casting.feature` - Ray casting for point picking

## Tags

Features use tags for categorization:

- `@file-handling` - File operations
- `@drag-and-drop` - Drag and drop file opening
- `@camera` - Camera controls
- `@visualization` - Display modes
- `@measurement` - Measurement tools
- `@slicing` - Slicing functionality
- `@leveling` - Leveling/transformation functionality
- `@material` - Material system
- `@3mf` - 3MF format specific
- `@openscad` - OpenSCAD integration
- `@2d` - 2D OpenSCAD file support
- `@go3mf` - go3mf integration
- `@ui` - User interface
- `@keyboard` - Keyboard shortcuts
- `@internal` - Internal implementation details

## Supported File Formats

| Format | Extension | Description |
|--------|-----------|-------------|
| STL | .stl | Binary and ASCII stereolithography |
| 3MF | .3mf | 3D Manufacturing Format with multi-plate support |
| OpenSCAD | .scad | OpenSCAD source files (requires OpenSCAD, 2D files auto-extruded) |
| go3mf YAML | .yaml/.yml | go3mf configuration files (requires go3mf) |

## Supported Printers (Build Plates)

### Bambu Lab
- X1C (256³ mm)
- P1S (256³ mm)
- A1 (256³ mm)
- A1 mini (180³ mm)
- H2D (450³ mm)

### Prusa
- MK4 (250x210x220 mm)
- Mini (180³ mm)

### Voron
- V0 (120³ mm)
- 2.4 (350³ mm)

### Creality
- Ender 3 (220x220x250 mm)

## Materials

| Material | Density (g/cm³) | Appearance |
|----------|-----------------|------------|
| PLA | 1.24 | Blue-gray, matte |
| ABS | 1.04 | Warm gray, slight gloss |
| PETG | 1.27 | Blue-tinted, glossy |
| TPU | 1.21 | Dark gray, very matte |
| Nylon | 1.14 | Cream/beige, moderate gloss |

## Quick Reference: Keyboard Shortcuts

### File Operations
| Shortcut | Action |
|----------|--------|
| Cmd+T | New tab with example cube |
| Cmd+O | Open file |
| Cmd+S | Save file (if modified) |
| Cmd+Shift+S | Save As... |
| Cmd+R | Reload current file |

### Camera
| Shortcut | Action |
|----------|--------|
| Cmd+1-6 | Front/Back/Left/Right/Top/Bottom view |
| Cmd+0 | Reset view |
| 7 | Home/isometric view |
| F | Frame model |
| ESC | Reset view (when nothing else active) |

### View Toggles
| Shortcut | Action |
|----------|--------|
| Cmd+I | Toggle info panel |
| Cmd+W | Cycle wireframe mode |
| Cmd+G | Cycle grid mode |
| Cmd+B | Cycle build plate |
| Cmd+Shift+X | Toggle slicing panel |

### Measurements
| Shortcut | Action |
|----------|--------|
| Cmd+D | Measure distance |
| Cmd+A | Measure angle |
| R | Measure radius |
| T | Select triangles |
| Cmd+drag | Paint select triangles (in triangle mode) |
| Option+Cmd+drag | Rectangle select triangles (in triangle mode) |
| X/Y/Z | Axis constraint (in measurement mode) |
| Backspace | Undo last point / delete selected |
| Cmd+Shift+K | Clear all measurements |
| Cmd+Shift+C | Copy selected/all as OpenSCAD |
| Cmd+P | Copy selected/all as polygon |

### Transformation
| Shortcut | Action |
|----------|--------|
| Cmd+L / L | Level object (align two points) |

### Other
| Shortcut | Action |
|----------|--------|
| Cmd+M | Cycle material |
| O | Open with go3mf |
| Ctrl+C | Quit application |
