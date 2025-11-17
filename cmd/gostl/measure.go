package main

import (
	"fmt"
	"os"

	"github.com/philipparndt/gostl/pkg/analysis"
	"github.com/philipparndt/gostl/pkg/geometry"
	"github.com/philipparndt/gostl/pkg/stl"
	"github.com/spf13/cobra"
)

var (
	point1X, point1Y, point1Z float64
	point2X, point2Y, point2Z float64
)

var measureCmd = &cobra.Command{
	Use:   "measure [file]",
	Short: "Measure distance between two points",
	Long: `Measure the straight-line distance between two 3D points.
Points can be specified directly, or the tool will find the nearest vertices in the model.`,
	Args: cobra.ExactArgs(1),
	Run:  runMeasure,
}

func init() {
	rootCmd.AddCommand(measureCmd)

	measureCmd.Flags().Float64Var(&point1X, "x1", 0.0, "X coordinate of first point")
	measureCmd.Flags().Float64Var(&point1Y, "y1", 0.0, "Y coordinate of first point")
	measureCmd.Flags().Float64Var(&point1Z, "z1", 0.0, "Z coordinate of first point")
	measureCmd.Flags().Float64Var(&point2X, "x2", 0.0, "X coordinate of second point")
	measureCmd.Flags().Float64Var(&point2Y, "y2", 0.0, "Y coordinate of second point")
	measureCmd.Flags().Float64Var(&point2Z, "z2", 0.0, "Z coordinate of second point")

	measureCmd.MarkFlagsRequiredTogether("x1", "y1", "z1", "x2", "y2", "z2")
}

func runMeasure(cmd *cobra.Command, args []string) {
	filename := args[0]

	p1 := geometry.NewVector3(point1X, point1Y, point1Z)
	p2 := geometry.NewVector3(point2X, point2Y, point2Z)

	model, err := stl.Parse(filename)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing STL file: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Point-to-Point Measurement")
	fmt.Println("==========================")

	// Find nearest vertices
	nearest1, dist1 := analysis.FindNearestVertex(model, p1)
	nearest2, dist2 := analysis.FindNearestVertex(model, p2)

	fmt.Printf("\nPoint 1: %s\n", analysis.FormatVector(p1))
	if dist1 > 0 {
		fmt.Printf("  Nearest vertex: %s (distance: %.6f)\n", analysis.FormatVector(nearest1), dist1)
	}

	fmt.Printf("\nPoint 2: %s\n", analysis.FormatVector(p2))
	if dist2 > 0 {
		fmt.Printf("  Nearest vertex: %s (distance: %.6f)\n", analysis.FormatVector(nearest2), dist2)
	}

	distance := analysis.DistanceBetweenPoints(p1, p2)
	fmt.Printf("\nDirect distance: %.6f units\n", distance)

	if dist1 > 0 || dist2 > 0 {
		vertexDistance := analysis.DistanceBetweenPoints(nearest1, nearest2)
		fmt.Printf("Distance between nearest vertices: %.6f units\n", vertexDistance)
	}
}
