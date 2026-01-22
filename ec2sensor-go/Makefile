.PHONY: build run clean test install all darwin linux windows

APP_NAME := ec2sensor
VERSION := 2.0.0
BUILD_DIR := build

# Default target
all: build

# Build for current platform
build:
	go build -ldflags "-X main.version=$(VERSION)" -o $(APP_NAME) .

# Run the application
run:
	go run .

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -f $(APP_NAME)
	rm -f $(APP_NAME)-*

# Run tests
test:
	go test -v ./...

# Install dependencies
deps:
	go mod download
	go mod tidy

# Build for macOS (both architectures)
darwin: darwin-arm64 darwin-amd64

darwin-arm64:
	@mkdir -p $(BUILD_DIR)
	GOOS=darwin GOARCH=arm64 go build -ldflags "-X main.version=$(VERSION)" -o $(BUILD_DIR)/$(APP_NAME)-darwin-arm64 .

darwin-amd64:
	@mkdir -p $(BUILD_DIR)
	GOOS=darwin GOARCH=amd64 go build -ldflags "-X main.version=$(VERSION)" -o $(BUILD_DIR)/$(APP_NAME)-darwin-amd64 .

# Build for Linux
linux: linux-amd64 linux-arm64

linux-amd64:
	@mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=amd64 go build -ldflags "-X main.version=$(VERSION)" -o $(BUILD_DIR)/$(APP_NAME)-linux-amd64 .

linux-arm64:
	@mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=arm64 go build -ldflags "-X main.version=$(VERSION)" -o $(BUILD_DIR)/$(APP_NAME)-linux-arm64 .

# Build for Windows
windows:
	@mkdir -p $(BUILD_DIR)
	GOOS=windows GOARCH=amd64 go build -ldflags "-X main.version=$(VERSION)" -o $(BUILD_DIR)/$(APP_NAME)-windows-amd64.exe .

# Build for all platforms
release: clean darwin linux windows
	@echo "Built releases in $(BUILD_DIR)/"
	@ls -la $(BUILD_DIR)/

# Install to /usr/local/bin (macOS/Linux)
install: build
	sudo cp $(APP_NAME) /usr/local/bin/
	@echo "Installed to /usr/local/bin/$(APP_NAME)"

# Development watch mode (requires entr)
watch:
	find . -name '*.go' | entr -r go run .

# Format code
fmt:
	go fmt ./...

# Lint code (requires golangci-lint)
lint:
	golangci-lint run

# Show help
help:
	@echo "EC2 Sensor Manager - Go Edition"
	@echo ""
	@echo "Usage:"
	@echo "  make build     - Build for current platform"
	@echo "  make run       - Run the application"
	@echo "  make clean     - Remove build artifacts"
	@echo "  make test      - Run tests"
	@echo "  make deps      - Download dependencies"
	@echo "  make darwin    - Build for macOS (arm64 + amd64)"
	@echo "  make linux     - Build for Linux (amd64 + arm64)"
	@echo "  make windows   - Build for Windows (amd64)"
	@echo "  make release   - Build for all platforms"
	@echo "  make install   - Install to /usr/local/bin"
	@echo "  make fmt       - Format Go code"
	@echo "  make lint      - Run linter"
