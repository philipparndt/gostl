.PHONY: build run clean test release install-dev restore-release

# Homebrew installation paths
BREW_PREFIX := $(shell brew --prefix gostl 2>/dev/null)
BREW_GOSTL := $(BREW_PREFIX)/bin/gostl
BREW_BACKUP := $(BREW_PREFIX)/bin/gostl.backup
BREW_APP := $(BREW_PREFIX)/GoSTL.app
BREW_METALLIB := $(BREW_APP)/GoSTL_GoSTL.bundle/Contents/Resources/default.metallib
BREW_METALLIB_BACKUP := $(BREW_APP)/GoSTL_GoSTL.bundle/Contents/Resources/default.metallib.backup

# Default target
all: build

# Build debug version
build:
	cd GoSTL-Swift && xcrun swift build
	cd GoSTL-Swift && xcrun -sdk macosx metal -c GoSTL/Resources/Shaders.metal -o .build/Shaders.air
	cd GoSTL-Swift && xcrun -sdk macosx metallib .build/Shaders.air -o .build/default.metallib
	mkdir -p GoSTL-Swift/.build/arm64-apple-macosx/debug/GoSTL_GoSTL.bundle/Contents/Resources
	cp GoSTL-Swift/.build/default.metallib GoSTL-Swift/.build/arm64-apple-macosx/debug/GoSTL_GoSTL.bundle/Contents/Resources/

# Build release version
release:
	cd GoSTL-Swift && xcrun swift build -c release --arch arm64
	cd GoSTL-Swift && xcrun -sdk macosx metal -c GoSTL/Resources/Shaders.metal -o .build/Shaders.air
	cd GoSTL-Swift && xcrun -sdk macosx metallib .build/Shaders.air -o .build/default.metallib
	mkdir -p GoSTL-Swift/.build/arm64-apple-macosx/release/GoSTL_GoSTL.bundle/Contents/Resources
	cp GoSTL-Swift/.build/default.metallib GoSTL-Swift/.build/arm64-apple-macosx/release/GoSTL_GoSTL.bundle/Contents/Resources/

# Run debug version with file argument
# Usage: make run FILE=./examples/cube.stl
run: build
	GoSTL-Swift/.build/arm64-apple-macosx/debug/GoSTL $(FILE)

# Run release version with file argument
run-release: release
	GoSTL-Swift/.build/arm64-apple-macosx/release/GoSTL $(FILE)

# Test with sample file
test: build
	GoSTL-Swift/.build/arm64-apple-macosx/debug/GoSTL examples/simple-named/PartA_1.stl

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
	sudo cp GoSTL-Swift/.build/arm64-apple-macosx/debug/GoSTL "$(BREW_GOSTL)"
	sudo cp GoSTL-Swift/.build/arm64-apple-macosx/debug/GoSTL "$(BREW_APP)/Contents/MacOS/GoSTL"
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
