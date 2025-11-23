.PHONY: build test clean install run run-scad help

# Variables
BINARY_NAME=gostl
BUILD_DIR=.
PKG_LIST=$(go list ./... | grep -v /vendor/)

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build the Raylib GPU-accelerated binary
	@echo "Building $(BINARY_NAME)..."
	@go build -o $(BUILD_DIR)/$(BINARY_NAME)
	@echo "Build complete: $(BUILD_DIR)/$(BINARY_NAME)"

test: ## Run tests
	@echo "Running tests..."
	@go test -v ./pkg/...

test-coverage: ## Run tests with coverage
	@echo "Running tests with coverage..."
	@go test -coverprofile=coverage.out ./pkg/...
	@go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

clean: ## Clean build artifacts
	@echo "Cleaning..."
	@rm -f $(BUILD_DIR)/$(BINARY_NAME)
	@rm -f coverage.out coverage.html
	@echo "Clean complete"

install: build ## Install the binary to $GOPATH/bin
	@echo "Installing $(BINARY_NAME)..."
	@go install
	@echo "Installed to $$(go env GOPATH)/bin/$(BINARY_NAME)"

run: build ## Build and run with example STL file
	@echo "Running $(BINARY_NAME)..."
	@./$(BINARY_NAME) ./examples/h2d-named/Large_Insert_13_6.stl

run-scad: build ## Build and run with example OpenSCAD file
	@echo "Running $(BINARY_NAME)..."
	@./$(BINARY_NAME) ~/dev/3d/filament/filament_holder_lip.scad

fmt: ## Format code
	@echo "Formatting code..."
	@go fmt ./...

lint: ## Run linter (requires golangci-lint)
	@echo "Running linter..."
	@golangci-lint run ./...

deps: ## Download dependencies
	@echo "Downloading dependencies..."
	@go mod download
	@go mod tidy

.DEFAULT_GOAL := help
