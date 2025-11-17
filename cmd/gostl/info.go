package main

import (
	"fmt"
	"os"

	"github.com/philipparndt/gostl/pkg/analysis"
	"github.com/philipparndt/gostl/pkg/stl"
	"github.com/spf13/cobra"
)

var infoCmd = &cobra.Command{
	Use:   "info [file]",
	Short: "Display general information about an STL file",
	Long:  "Show comprehensive information including dimensions, triangle count, surface area, and edge statistics.",
	Args:  cobra.ExactArgs(1),
	Run:   runInfo,
}

func init() {
	rootCmd.AddCommand(infoCmd)
}

func runInfo(cmd *cobra.Command, args []string) {
	filename := args[0]

	model, err := stl.Parse(filename)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing STL file: %v\n", err)
		os.Exit(1)
	}

	result := analysis.AnalyzeModel(model)

	fmt.Println("STL File Information")
	fmt.Println("====================")
	if model.Name != "" {
		fmt.Printf("Name: %s\n", model.Name)
	}
	fmt.Printf("File: %s\n\n", filename)

	fmt.Println("Model Statistics:")
	fmt.Printf("  Triangles: %d\n", result.TriangleCount)
	fmt.Printf("  Edges: %d\n", result.EdgeCount)
	fmt.Printf("  Surface Area: %.6f square units\n\n", result.SurfaceArea)

	fmt.Println("Bounding Box:")
	fmt.Printf("  Min: %s\n", analysis.FormatVector(result.BoundingBox.Min))
	fmt.Printf("  Max: %s\n", analysis.FormatVector(result.BoundingBox.Max))
	fmt.Printf("  Center: %s\n\n", analysis.FormatVector(result.BoundingBox.Center()))

	fmt.Println("Dimensions:")
	fmt.Printf("  Width (X): %.6f units\n", result.Dimensions.X)
	fmt.Printf("  Depth (Y): %.6f units\n", result.Dimensions.Y)
	fmt.Printf("  Height (Z): %.6f units\n", result.Dimensions.Z)
	fmt.Printf("  Diagonal: %.6f units\n", result.BoundingBox.Diagonal())
	fmt.Printf("  Volume: %.6f cubic units\n\n", result.Volume)

	fmt.Println("Edge Lengths:")
	fmt.Printf("  Minimum: %.6f units\n", result.MinEdgeLength)
	fmt.Printf("  Maximum: %.6f units\n", result.MaxEdgeLength)
	fmt.Printf("  Average: %.6f units\n", result.AvgEdgeLength)
}
