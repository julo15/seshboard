.PHONY: build build-release run-app run-cli test test-core test-ui clean resolve kill-build install restart

# Build
build:
	swift build

build-release:
	swift build -c release

# Run
run-app:
	swift run SeshboardApp

run-cli:
	swift run seshboard-cli $(ARGS)

# Test
test:
	swift test

test-core:
	swift test --filter SeshboardCoreTests

test-ui:
	swift test --filter SeshboardUITests

# Install & restart
install: build-release
	cp .build/release/seshboard-cli ~/.local/bin/seshboard-cli

restart: build-release
	pkill -f SeshboardApp || true
	sleep 0.5
	.build/release/SeshboardApp &

# Maintenance
clean:
	swift package clean

resolve:
	swift package resolve

kill-build:
	pkill -9 -f swift-build || true
	pkill -9 -f swift-test || true
	pkill -9 -f swift-frontend || true
	@echo "killed stale SwiftPM processes"
