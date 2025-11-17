.PHONY: build build-gui build-all test clean install install-all run run-gui help

# Variables
BINARY_NAME=gostl
GUI_BINARY_NAME=gostl-gui
BUILD_DIR=.
CMD_DIR=./cmd/gostl
GUI_CMD_DIR=./cmd/gostl-gui
PKG_LIST=$$(go list ./... | grep -v /vendor/)

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build the CLI binary
	@echo "Building $(BINARY_NAME)..."
	@go build -o $(BUILD_DIR)/$(BINARY_NAME) $(CMD_DIR)
	@echo "Build complete: $(BUILD_DIR)/$(BINARY_NAME)"

build-gui: ## Build the GUI binary
	@echo "Building $(GUI_BINARY_NAME)..."
	@go build -o $(BUILD_DIR)/$(GUI_BINARY_NAME) $(GUI_CMD_DIR)
	@echo "Build complete: $(BUILD_DIR)/$(GUI_BINARY_NAME)"

build-all: build build-gui ## Build both CLI and GUI binaries
	@echo "All builds complete"

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
	@rm -f $(BUILD_DIR)/$(GUI_BINARY_NAME)
	@rm -f coverage.out coverage.html
	@echo "Clean complete"

install: build ## Install the CLI binary to $GOPATH/bin
	@echo "Installing $(BINARY_NAME)..."
	@go install $(CMD_DIR)
	@echo "Installed to $$(go env GOPATH)/bin/$(BINARY_NAME)"

install-gui: build-gui ## Install the GUI binary to $GOPATH/bin
	@echo "Installing $(GUI_BINARY_NAME)..."
	@go install $(GUI_CMD_DIR)
	@echo "Installed to $$(go env GOPATH)/bin/$(GUI_BINARY_NAME)"

install-all: install install-gui ## Install both CLI and GUI binaries
	@echo "All installations complete"

run: build ## Build and run CLI with help
	@echo "Running $(BINARY_NAME) --help"
	@./$(BINARY_NAME) --help

run-gui: build-gui ## Build and run GUI with example
	@echo "Running $(GUI_BINARY_NAME)..."
	@./$(GUI_BINARY_NAME) examples/cube.stl

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
