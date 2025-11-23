package app

import (
	"fmt"
	"os/exec"
)

// openWithGo3mf opens the current file with go3mf
func (app *App) openWithGo3mf() {
	if app.FileWatch.sourceFile == "" {
		fmt.Println("No file loaded")
		return
	}

	// Check if go3mf is installed
	if _, err := exec.LookPath("go3mf"); err != nil {
		fmt.Println("go3mf not found in PATH. Please install go3mf first.")
		return
	}

	fmt.Printf("Opening %s with go3mf...\n", app.FileWatch.sourceFile)

	// Execute go3mf build <filename> --open
	cmd := exec.Command("go3mf", "build", app.FileWatch.sourceFile, "--open")

	// Start the command without waiting for it to complete
	err := cmd.Start()
	if err != nil {
		fmt.Printf("Error launching go3mf: %v\n", err)
		return
	}

	fmt.Println("go3mf command launched successfully")
}
