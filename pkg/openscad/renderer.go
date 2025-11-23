package openscad

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// Renderer handles OpenSCAD file rendering to STL
type Renderer struct {
	workDir string
}

// NewRenderer creates a new OpenSCAD renderer
func NewRenderer(workDir string) *Renderer {
	return &Renderer{
		workDir: workDir,
	}
}

// RenderToSTL renders an OpenSCAD file to STL format
func (r *Renderer) RenderToSTL(scadFile, outputFile string) error {
	// Convert scadFile to absolute path if it's relative
	absScadFile := scadFile
	if !filepath.IsAbs(scadFile) {
		absScadFile = filepath.Join(r.workDir, scadFile)
	}

	// Check if OpenSCAD is installed
	if _, err := exec.LookPath("openscad"); err != nil {
		return fmt.Errorf("openscad not found in PATH. Please install OpenSCAD from https://openscad.org/")
	}

	cmd := exec.Command("openscad", "-o", outputFile, absScadFile)
	cmd.Dir = r.workDir

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()

	// If error occurred, display output
	if err != nil {
		var errMsg strings.Builder
		errMsg.WriteString(fmt.Sprintf("failed to render %s: %v\n", scadFile, err))
		if stderr.Len() > 0 {
			errMsg.WriteString("stderr: ")
			errMsg.WriteString(stderr.String())
		}
		if stdout.Len() > 0 {
			errMsg.WriteString("stdout: ")
			errMsg.WriteString(stdout.String())
		}
		return fmt.Errorf("%s", errMsg.String())
	}

	return nil
}

// ResolveDependencies finds all dependencies (use/include statements) in an OpenSCAD file
// Returns a list of absolute paths to all dependencies
func (r *Renderer) ResolveDependencies(scadFile string) ([]string, error) {
	absScadFile := scadFile
	if !filepath.IsAbs(scadFile) {
		absScadFile = filepath.Join(r.workDir, scadFile)
	}

	visited := make(map[string]bool)
	var deps []string

	if err := r.resolveDependenciesRecursive(absScadFile, visited, &deps); err != nil {
		return nil, err
	}

	return deps, nil
}

// resolveDependenciesRecursive recursively finds all dependencies
func (r *Renderer) resolveDependenciesRecursive(scadFile string, visited map[string]bool, deps *[]string) error {
	// Avoid circular dependencies
	if visited[scadFile] {
		return nil
	}
	visited[scadFile] = true

	// Add this file to dependencies
	*deps = append(*deps, scadFile)

	// Parse the file to find use/include statements
	fileDeps, err := r.parseDependencies(scadFile)
	if err != nil {
		return err
	}

	// Recursively resolve dependencies
	for _, dep := range fileDeps {
		if err := r.resolveDependenciesRecursive(dep, visited, deps); err != nil {
			return err
		}
	}

	return nil
}

// parseDependencies parses a single OpenSCAD file to find use/include statements
func (r *Renderer) parseDependencies(scadFile string) ([]string, error) {
	file, err := os.Open(scadFile)
	if err != nil {
		return nil, fmt.Errorf("failed to open %s: %w", scadFile, err)
	}
	defer file.Close()

	var deps []string
	scanner := bufio.NewScanner(file)

	// Regular expressions to match use/include statements
	// Matches: use <file.scad>, include <file.scad>, use <./file.scad>, etc.
	useRegex := regexp.MustCompile(`^\s*use\s*<([^>]+)>`)
	includeRegex := regexp.MustCompile(`^\s*include\s*<([^>]+)>`)

	scadDir := filepath.Dir(scadFile)

	for scanner.Scan() {
		line := scanner.Text()

		// Skip comments
		if strings.HasPrefix(strings.TrimSpace(line), "//") {
			continue
		}

		// Check for use statement
		if matches := useRegex.FindStringSubmatch(line); len(matches) > 1 {
			depPath := r.resolveDepPath(matches[1], scadDir)
			deps = append(deps, depPath)
		}

		// Check for include statement
		if matches := includeRegex.FindStringSubmatch(line); len(matches) > 1 {
			depPath := r.resolveDepPath(matches[1], scadDir)
			deps = append(deps, depPath)
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading %s: %w", scadFile, err)
	}

	return deps, nil
}

// resolveDepPath resolves a dependency path relative to the current file's directory
func (r *Renderer) resolveDepPath(depPath, currentDir string) string {
	// If the path starts with ./ or ../, it's relative to the current file
	if strings.HasPrefix(depPath, "./") || strings.HasPrefix(depPath, "../") {
		absPath := filepath.Join(currentDir, depPath)
		return filepath.Clean(absPath)
	}

	// Otherwise, try relative to current directory first
	absPath := filepath.Join(currentDir, depPath)
	if _, err := os.Stat(absPath); err == nil {
		return filepath.Clean(absPath)
	}

	// Try relative to work directory
	absPath = filepath.Join(r.workDir, depPath)
	return filepath.Clean(absPath)
}
