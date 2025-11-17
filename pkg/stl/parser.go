package stl

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/philipparndt/gostl/pkg/geometry"
)

// Parse reads an STL file and returns a Model
// It automatically detects whether the file is ASCII or binary format
func Parse(filename string) (*Model, error) {
	file, err := os.Open(filename)
	if err != nil {
		return nil, fmt.Errorf("failed to open file: %w", err)
	}
	defer file.Close()

	// Read first few bytes to determine format
	header := make([]byte, 6)
	n, err := file.Read(header)
	if err != nil {
		return nil, fmt.Errorf("failed to read file header: %w", err)
	}

	// Reset file pointer
	if _, err := file.Seek(0, 0); err != nil {
		return nil, fmt.Errorf("failed to reset file pointer: %w", err)
	}

	// Check if it's ASCII format (starts with "solid ")
	if n >= 5 && strings.HasPrefix(string(header[:5]), "solid") {
		return parseASCII(file)
	}

	return parseBinary(file)
}

// parseASCII parses an ASCII STL file
func parseASCII(reader io.Reader) (*Model, error) {
	scanner := bufio.NewScanner(reader)
	model := NewModel("")

	var currentNormal geometry.Vector3
	var vertices []geometry.Vector3

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		fields := strings.Fields(line)

		if len(fields) == 0 {
			continue
		}

		switch fields[0] {
		case "solid":
			if len(fields) > 1 {
				model.Name = strings.Join(fields[1:], " ")
			}

		case "facet":
			if len(fields) >= 5 && fields[1] == "normal" {
				x, _ := strconv.ParseFloat(fields[2], 64)
				y, _ := strconv.ParseFloat(fields[3], 64)
				z, _ := strconv.ParseFloat(fields[4], 64)
				currentNormal = geometry.NewVector3(x, y, z)
			}

		case "vertex":
			if len(fields) >= 4 {
				x, _ := strconv.ParseFloat(fields[1], 64)
				y, _ := strconv.ParseFloat(fields[2], 64)
				z, _ := strconv.ParseFloat(fields[3], 64)
				vertices = append(vertices, geometry.NewVector3(x, y, z))
			}

		case "endfacet":
			if len(vertices) == 3 {
				triangle := geometry.NewTriangle(
					currentNormal,
					vertices[0],
					vertices[1],
					vertices[2],
				)
				model.AddTriangle(triangle)
			}
			vertices = vertices[:0] // Clear vertices
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading ASCII STL: %w", err)
	}

	return model, nil
}

// parseBinary parses a binary STL file
func parseBinary(reader io.Reader) (*Model, error) {
	model := NewModel("")

	// Read 80-byte header
	header := make([]byte, 80)
	if _, err := io.ReadFull(reader, header); err != nil {
		return nil, fmt.Errorf("failed to read header: %w", err)
	}

	// Extract name from header (if present)
	headerStr := string(bytes.TrimRight(header, "\x00"))
	if len(headerStr) > 0 {
		model.Name = headerStr
	}

	// Read triangle count
	var triangleCount uint32
	if err := binary.Read(reader, binary.LittleEndian, &triangleCount); err != nil {
		return nil, fmt.Errorf("failed to read triangle count: %w", err)
	}

	// Read each triangle
	for i := uint32(0); i < triangleCount; i++ {
		var normal, v1, v2, v3 [3]float32
		var attributeByteCount uint16

		// Read normal
		if err := binary.Read(reader, binary.LittleEndian, &normal); err != nil {
			return nil, fmt.Errorf("failed to read normal for triangle %d: %w", i, err)
		}

		// Read vertices
		if err := binary.Read(reader, binary.LittleEndian, &v1); err != nil {
			return nil, fmt.Errorf("failed to read v1 for triangle %d: %w", i, err)
		}
		if err := binary.Read(reader, binary.LittleEndian, &v2); err != nil {
			return nil, fmt.Errorf("failed to read v2 for triangle %d: %w", i, err)
		}
		if err := binary.Read(reader, binary.LittleEndian, &v3); err != nil {
			return nil, fmt.Errorf("failed to read v3 for triangle %d: %w", i, err)
		}

		// Read attribute byte count (usually unused, but required by format)
		if err := binary.Read(reader, binary.LittleEndian, &attributeByteCount); err != nil {
			return nil, fmt.Errorf("failed to read attribute for triangle %d: %w", i, err)
		}

		// Create triangle and add to model
		triangle := geometry.NewTriangle(
			geometry.NewVector3(float64(normal[0]), float64(normal[1]), float64(normal[2])),
			geometry.NewVector3(float64(v1[0]), float64(v1[1]), float64(v1[2])),
			geometry.NewVector3(float64(v2[0]), float64(v2[1]), float64(v2[2])),
			geometry.NewVector3(float64(v3[0]), float64(v3[1]), float64(v3[2])),
		)
		model.AddTriangle(triangle)
	}

	return model, nil
}
