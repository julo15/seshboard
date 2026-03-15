.PHONY: build build-release run-app run-cli test test-core test-ui clean resolve

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

# Maintenance
clean:
	swift package clean

resolve:
	swift package resolve
