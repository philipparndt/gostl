.PHONY: help build run run-release clean test release install-dev restore-release install-status

# Where SwiftPM puts the built products.
#
# Asked rather than assumed: the layout moved from .build/<triple>/<config> to
# .build/out/Products/<Config>, and a hard-coded path does not fail - it runs
# whatever stale binary is still sitting at the old one. Evaluated lazily, so
# targets that build nothing (help, clean) do not pay for the query.
DEBUG_BIN = $(shell cd GoSTL-Swift && xcrun swift build --show-bin-path)
RELEASE_BIN = $(shell cd GoSTL-Swift && xcrun swift build -c release --arch arm64 --show-bin-path)

# Homebrew installation paths
BREW_PREFIX := $(shell brew --prefix gostl 2>/dev/null)
BREW_GOSTL := $(BREW_PREFIX)/bin/gostl
BREW_BACKUP := $(BREW_PREFIX)/bin/gostl.backup
BREW_APP := $(BREW_PREFIX)/GoSTL.app
BREW_METALLIB := $(BREW_APP)/GoSTL_GoSTL.bundle/Contents/Resources/default.metallib
BREW_METALLIB_BACKUP := $(BREW_APP)/GoSTL_GoSTL.bundle/Contents/Resources/default.metallib.backup

# Default target
all: build

# Show available targets
help:
	@echo "GoSTL Makefile targets:"
	@echo ""
	@echo "  build            Build debug version (compiles Swift + Metal shaders)"
	@echo "  release          Build release version (arm64)"
	@echo "  run FILE=<path>  Build debug and run with the given file"
	@echo "  run-release FILE=<path>"
	@echo "                   Build release and run with the given file"
	@echo "  test             Build debug and open examples/simple-named/PartA_1.stl"
	@echo "  clean            Remove build artifacts (.build/)"
	@echo "  install-dev      Replace the Homebrew binary with the local debug build"
	@echo "                   (creates a backup the first time)"
	@echo "  restore-release  Restore the Homebrew release binary from backup"
	@echo "  install-status   Show whether the Homebrew install is dev or release"
	@echo "  help             Show this help"

# Build debug version
build:
	cd GoSTL-Swift && xcrun swift build
	cd GoSTL-Swift && xcrun -sdk macosx metal -c GoSTL/Resources/Shaders.metal -o .build/Shaders.air
	cd GoSTL-Swift && xcrun -sdk macosx metallib .build/Shaders.air -o .build/default.metallib
	BIN="$(DEBUG_BIN)"; mkdir -p "$$BIN/GoSTL_GoSTL.bundle/Contents/Resources" && cp GoSTL-Swift/.build/default.metallib "$$BIN/GoSTL_GoSTL.bundle/Contents/Resources/"

# Build release version
release:
	cd GoSTL-Swift && xcrun swift build -c release --arch arm64
	cd GoSTL-Swift && xcrun -sdk macosx metal -c GoSTL/Resources/Shaders.metal -o .build/Shaders.air
	cd GoSTL-Swift && xcrun -sdk macosx metallib .build/Shaders.air -o .build/default.metallib
	BIN="$(RELEASE_BIN)"; mkdir -p "$$BIN/GoSTL_GoSTL.bundle/Contents/Resources" && cp GoSTL-Swift/.build/default.metallib "$$BIN/GoSTL_GoSTL.bundle/Contents/Resources/"

# Run debug version with file argument
# Usage: make run FILE=./examples/cube.stl
run: build
	"$(DEBUG_BIN)/GoSTL" $(FILE)

# Run release version with file argument
run-release: release
	"$(RELEASE_BIN)/GoSTL" $(FILE)

# Test with sample file
test: build
	"$(DEBUG_BIN)/GoSTL" examples/simple-named/PartA_1.stl

# Clean build artifacts
clean:
	rm -rf GoSTL-Swift/.build

# Install dev build over Homebrew version (for testing)
# Creates a backup of the release version first
install-dev: build
	@if [ -z "$(BREW_PREFIX)" ] || [ ! -f "$(BREW_GOSTL)" ]; then \
		echo "Error: Homebrew GoSTL not found. Install with: brew install gostl"; \
		exit 1; \
	fi
	@if [ ! -f "$(BREW_BACKUP)" ]; then \
		echo "Backing up release version (may require sudo)..."; \
		sudo cp "$(BREW_GOSTL)" "$(BREW_BACKUP)"; \
		sudo cp "$(BREW_METALLIB)" "$(BREW_METALLIB_BACKUP)"; \
		sudo cp "$(BREW_APP)/Contents/MacOS/GoSTL" "$(BREW_APP)/Contents/MacOS/GoSTL.backup"; \
	else \
		echo "Backup already exists"; \
	fi
	@echo "Installing dev build (may require sudo)..."
	BIN="$(DEBUG_BIN)"; sudo cp "$$BIN/GoSTL" "$(BREW_GOSTL)" && sudo cp "$$BIN/GoSTL" "$(BREW_APP)/Contents/MacOS/GoSTL"
	sudo cp GoSTL-Swift/.build/default.metallib "$(BREW_METALLIB)"
	@echo ""
	@echo "Done! Dev build installed."
	@echo "  - Quit GoSTL if running"
	@echo "  - Test by opening files from Finder"
	@echo "  - Run 'make restore-release' when done testing"

# Restore the Homebrew release version
restore-release:
	@if [ -z "$(BREW_PREFIX)" ] || [ ! -f "$(BREW_BACKUP)" ]; then \
		echo "Error: No backup found. Nothing to restore."; \
		echo "Try: brew reinstall gostl"; \
		exit 1; \
	fi
	@echo "Restoring release version (may require sudo)..."
	sudo cp "$(BREW_BACKUP)" "$(BREW_GOSTL)"
	@if [ -f "$(BREW_METALLIB_BACKUP)" ]; then \
		sudo cp "$(BREW_METALLIB_BACKUP)" "$(BREW_METALLIB)"; \
	fi
	@if [ -f "$(BREW_APP)/Contents/MacOS/GoSTL.backup" ]; then \
		sudo cp "$(BREW_APP)/Contents/MacOS/GoSTL.backup" "$(BREW_APP)/Contents/MacOS/GoSTL"; \
	fi
	sudo rm -f "$(BREW_BACKUP)" "$(BREW_METALLIB_BACKUP)" "$(BREW_APP)/Contents/MacOS/GoSTL.backup"
	@echo "Done! Release version restored."

# Show current installation status
install-status:
	@echo "Homebrew prefix: $(BREW_PREFIX)"
	@echo "Binary: $(BREW_GOSTL)"
	@echo "App: $(BREW_APP)"
	@if [ -f "$(BREW_BACKUP)" ]; then \
		echo "Status: DEV build installed (backup exists)"; \
	else \
		echo "Status: Release build installed"; \
	fi
