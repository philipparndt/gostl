package main

import (
	"fmt"
	"os"

	"github.com/philipparndt/gostl/pkg/analysis"
	"github.com/philipparndt/gostl/pkg/stl"
	"github.com/spf13/cobra"
)

var (
	edgesCount     int
	edgesLongest   bool
	edgesShortest  bool
	edgesMinLength float64
	edgesMaxLength float64
)

var edgesCmd = &cobra.Command{
	Use:   "edges [file]",
	Short: "Analyze and measure edges in an STL file",
	Long:  "Find and measure edges, including longest, shortest, or edges within a specific length range.",
	Args:  cobra.ExactArgs(1),
	Run:   runEdges,
}

func init() {
	rootCmd.AddCommand(edgesCmd)

	edgesCmd.Flags().IntVarP(&edgesCount, "count", "n", 10, "Number of edges to display")
	edgesCmd.Flags().BoolVarP(&edgesLongest, "longest", "l", false, "Show longest edges")
	edgesCmd.Flags().BoolVarP(&edgesShortest, "shortest", "s", false, "Show shortest edges")
	edgesCmd.Flags().Float64Var(&edgesMinLength, "min", 0.0, "Minimum edge length filter")
	edgesCmd.Flags().Float64Var(&edgesMaxLength, "max", 0.0, "Maximum edge length filter")
}

func runEdges(cmd *cobra.Command, args []string) {
	filename := args[0]

	model, err := stl.Parse(filename)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing STL file: %v\n", err)
		os.Exit(1)
	}

	result := analysis.AnalyzeModel(model)

	var edges []analysis.EdgeInfo
	var title string

	if edgesLongest {
		edges = analysis.FindLongestEdges(result, edgesCount)
		title = fmt.Sprintf("Top %d Longest Edges", len(edges))
	} else if edgesShortest {
		edges = analysis.FindShortestEdges(result, edgesCount)
		title = fmt.Sprintf("Top %d Shortest Edges", len(edges))
	} else if edgesMaxLength > 0 {
		edges = analysis.FindEdgesByLength(result, edgesMinLength, edgesMaxLength)
		title = fmt.Sprintf("Edges between %.6f and %.6f units (found %d)", edgesMinLength, edgesMaxLength, len(edges))
		if len(edges) > edgesCount {
			edges = edges[:edgesCount]
		}
	} else {
		edges = result.AllEdges
		title = fmt.Sprintf("All Edges (showing first %d of %d)", edgesCount, len(edges))
		if len(edges) > edgesCount {
			edges = edges[:edgesCount]
		}
	}

	fmt.Println(title)
	fmt.Println("====================")
	fmt.Printf("Total edges in model: %d\n", result.EdgeCount)
	fmt.Printf("Min edge length: %.6f units\n", result.MinEdgeLength)
	fmt.Printf("Max edge length: %.6f units\n", result.MaxEdgeLength)
	fmt.Printf("Avg edge length: %.6f units\n\n", result.AvgEdgeLength)

	if len(edges) > 0 {
		fmt.Printf("%-6s %-35s %-35s %-15s\n", "Index", "Start", "End", "Length")
		fmt.Println("-----------------------------------------------------------------------------------------------------------")
		for i, edge := range edges {
			fmt.Printf("%-6d %-35s %-35s %-15.6f\n",
				i+1,
				analysis.FormatVector(edge.Start),
				analysis.FormatVector(edge.End),
				edge.Length)
		}
	} else {
		fmt.Println("No edges found matching the criteria.")
	}
}
