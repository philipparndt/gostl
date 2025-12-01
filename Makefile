.PHONY: build run clean test release

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
