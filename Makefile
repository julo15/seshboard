.DEFAULT_GOAL := help
.PHONY: help build build-release run-app run-cli test test-core test-ui clean resolve kill-build install restart

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

build: ## Build debug
	swift build

build-release: ## Build release
	swift build -c release

run-app: ## Run app (debug)
	swift run SeshboardApp

run-cli: ## Run CLI (debug), e.g. make run-cli ARGS="list"
	swift run seshboard-cli $(ARGS)

test: ## Run all tests
	swift test

test-core: ## Run SeshboardCore tests
	swift test --filter SeshboardCoreTests

test-ui: ## Run SeshboardUI tests
	swift test --filter SeshboardUITests

install: build-release ## Build release + install CLI to ~/.local/bin
	cp .build/release/seshboard-cli ~/.local/bin/seshboard-cli

restart: build-release ## Build release + restart SeshboardApp
	pkill -f SeshboardApp || true
	sleep 0.5
	.build/release/SeshboardApp &

clean: ## Clean build artifacts
	swift package clean

resolve: ## Resolve package dependencies
	swift package resolve

kill-build: ## Force-kill stale SwiftPM processes
	pkill -9 -f swift-build || true
	pkill -9 -f swift-test || true
	pkill -9 -f swift-frontend || true
	@echo "killed stale SwiftPM processes"
