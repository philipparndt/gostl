# Quick Start Guide

Get started with GoSTL in under 5 minutes!

## 1. Build the Applications

```bash
# Build both CLI and GUI
make build-all
```

Or build individually:
```bash
# Just the CLI
make build

# Just the GUI
make build-gui
```

## 2. Try the GUI (Recommended for First-Time Users)

Launch the GUI with the example cube:

```bash
./gostl-gui examples/cube.stl
```

**What you'll see:**
- A 3D wireframe view of a cube
- Model information panel on the right
- Instructions for controls

**Try this:**
1. **Drag** the mouse to rotate the cube
2. **Scroll** to zoom in/out
3. **Click** on a corner vertex (you'll see a red dot)
4. **Click** on another corner (you'll see a green dot)
5. Check the measurement panel - you'll see:
   - X, Y, Z distances
   - Total distance between the two points

For the example cube (10x10x10 units), the diagonal between opposite corners should be ~17.32 units!

## 3. Try the CLI

Get model information:
```bash
./gostl info examples/cube.stl
```

Find the longest edges:
```bash
./gostl edges examples/cube.stl --longest -n 5
```

Measure distance between two points:
```bash
./gostl measure examples/cube.stl \
  --x1 0 --y1 0 --z1 0 \
  --x2 10 --y2 10 --z2 10
```

## 4. Use with Your Own STL Files

### GUI:
```bash
# Open with file dialog
./gostl-gui

# Or specify file directly
./gostl-gui /path/to/your/model.stl
```

### CLI:
```bash
./gostl info /path/to/your/model.stl
```

## Common Use Cases

### Verify 3D Print Dimensions
1. Load your STL in the GUI
2. Click on key points (screw holes, mounting points, etc.)
3. Verify the distances match your design

### Find the Longest Edge
```bash
./gostl edges model.stl --longest -n 1
```

### Check Model Bounds
```bash
./gostl info model.stl
```
Look for the "Dimensions" section to see X, Y, Z sizes.

### Measure Specific Features
1. Open in GUI
2. Rotate to view the feature clearly
3. Click on the two points you want to measure
4. Read the X/Y/Z distances to understand the orientation

## Tips

- **GUI Performance**: Larger models (>10,000 triangles) may render slowly. The wireframe renderer is optimized for clarity, not speed.
- **Point Selection**: Zoom in close to select the exact vertex you want
- **Clear Selection**: Use the "Clear Selection" button to start over
- **CLI for Batch**: Use CLI commands in scripts to analyze multiple files

## Next Steps

- Read the full [README.md](README.md) for all CLI commands
- Check the [Architecture section](README.md#architecture) to understand the code structure
- Explore the `pkg/` directory to use GoSTL as a library in your own projects

## Need Help?

- Run `./gostl --help` to see all CLI commands
- Run `./gostl [command] --help` for specific command help
- Open an issue on GitHub if you find bugs or have questions
