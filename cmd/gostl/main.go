package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "gostl",
	Short: "A modern CLI tool for inspecting and measuring STL files",
	Long: `gostl is a powerful command-line tool for analyzing STL (Stereolithography) files.
It supports both ASCII and binary STL formats and provides precise measurements
for edges, surfaces, dimensions, and geometric properties.`,
	Version: "1.0.0",
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
