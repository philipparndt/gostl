package main

import (
	"fmt"
	"math"
	"os"
	"sort"

	"github.com/philipparndt/gostl/pkg/analysis"
	"github.com/philipparndt/gostl/pkg/stl"
	"github.com/spf13/cobra"
)

var (
	triCount   int
	triLargest bool
	triSmallest bool
)

type triangleInfo struct {
	Index     int
	Area      float64
	Perimeter float64
	Vertices  string
}

var trianglesCmd = &cobra.Command{
	Use:   "triangles [file]",
	Short: "Analyze triangles in an STL file",
	Long:  "Display information about triangles including area, perimeter, and vertex positions.",
	Args:  cobra.ExactArgs(1),
	Run:   runTriangles,
}

func init() {
	rootCmd.AddCommand(trianglesCmd)

	trianglesCmd.Flags().IntVarP(&triCount, "count", "n", 10, "Number of triangles to display")
	trianglesCmd.Flags().BoolVarP(&triLargest, "largest", "l", false, "Show largest triangles by area")
	trianglesCmd.Flags().BoolVarP(&triSmallest, "smallest", "s", false, "Show smallest triangles by area")
}

func runTriangles(cmd *cobra.Command, args []string) {
	filename := args[0]

	model, err := stl.Parse(filename)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing STL file: %v\n", err)
		os.Exit(1)
	}

	// Collect triangle info
	triangles := make([]triangleInfo, 0, len(model.Triangles))
	totalArea := 0.0
	minArea := math.MaxFloat64
	maxArea := 0.0

	for i, tri := range model.Triangles {
		area := tri.Area()
		perimeter := tri.Perimeter()

		triangles = append(triangles, triangleInfo{
			Index:     i,
			Area:      area,
			Perimeter: perimeter,
			Vertices: fmt.Sprintf("%s, %s, %s",
				analysis.FormatVector(tri.V1),
				analysis.FormatVector(tri.V2),
				analysis.FormatVector(tri.V3)),
		})

		totalArea += area
		if area < minArea {
			minArea = area
		}
		if area > maxArea {
			maxArea = area
		}
	}

	// Sort based on flags
	if triLargest {
		sort.Slice(triangles, func(i, j int) bool {
			return triangles[i].Area > triangles[j].Area
		})
	} else if triSmallest {
		sort.Slice(triangles, func(i, j int) bool {
			return triangles[i].Area < triangles[j].Area
		})
	}

	// Display results
	var title string
	if triLargest {
		title = fmt.Sprintf("Top %d Largest Triangles", triCount)
	} else if triSmallest {
		title = fmt.Sprintf("Top %d Smallest Triangles", triCount)
	} else {
		title = fmt.Sprintf("First %d Triangles", triCount)
	}

	fmt.Println(title)
	fmt.Println("====================")
	fmt.Printf("Total triangles: %d\n", len(triangles))
	fmt.Printf("Total surface area: %.6f square units\n", totalArea)
	fmt.Printf("Min triangle area: %.6f square units\n", minArea)
	fmt.Printf("Max triangle area: %.6f square units\n", maxArea)
	fmt.Printf("Avg triangle area: %.6f square units\n\n", totalArea/float64(len(triangles)))

	if triCount > len(triangles) {
		triCount = len(triangles)
	}

	for i := 0; i < triCount && i < len(triangles); i++ {
		tri := triangles[i]
		fmt.Printf("Triangle #%d:\n", tri.Index)
		fmt.Printf("  Area: %.6f square units\n", tri.Area)
		fmt.Printf("  Perimeter: %.6f units\n", tri.Perimeter)
		fmt.Printf("  Vertices: %s\n\n", tri.Vertices)
	}
}
