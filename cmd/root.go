package cmd

import (
	"fmt"
	"os"

	"github.com/philipparndt/gostl/internal/app"
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "gostl <file>",
	Short: "3D model file combiner and SCAD renderer",
	Long:  `GoSTL is a 3D model viewer and renderer that supports STL and OpenSCAD files.`,
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		// Set the file path in os.Args for the app.Run() to pick up
		os.Args = append([]string{os.Args[0]}, args[0])
		app.Run()
	},
}

// Execute runs the root command
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
