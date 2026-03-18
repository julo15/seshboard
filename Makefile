.DEFAULT_GOAL := help
.PHONY: help build build-release run-app run-cli test test-core test-ui clean resolve kill-build install install-cli install-app install-hooks

# Colors
CYAN   := \033[36m
DIM    := \033[2m
BOLD   := \033[1m
RESET  := \033[0m

help:
	@printf "$(BOLD)seshboard$(RESET) $(DIM)commands$(RESET)\n\n"
	@printf "  $(DIM)build$(RESET)\n"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "build" "Build debug"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "build-release" "Build release"
	@echo ""
	@printf "  $(DIM)run$(RESET)\n"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "run-app" "Run app (debug)"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "run-cli" "Run CLI (debug), e.g. make run-cli ARGS=\"list\""
	@echo ""
	@printf "  $(DIM)test$(RESET)\n"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "test" "Run all tests"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "test-core" "Run SeshboardCore tests"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "test-ui" "Run SeshboardUI tests"
	@echo ""
	@printf "  $(DIM)install$(RESET)\n"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "install" "Build release + install CLI + hooks + restart app"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "install-cli" "Build release + install CLI to ~/.local/bin"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "install-app" "Build release + restart SeshboardApp"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "install-hooks" "Register Claude Code and Codex hooks"
	@echo ""
	@printf "  $(DIM)maintenance$(RESET)\n"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "clean" "Clean build artifacts"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "resolve" "Resolve package dependencies"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "kill-build" "Force-kill stale SwiftPM processes"
	@echo ""

build:
	swift build

build-release:
	swift build -c release

run-app:
	swift run SeshboardApp

run-cli:
	swift run seshboard-cli $(ARGS)

test:
	swift test

test-core:
	swift test --filter SeshboardCoreTests

test-ui:
	swift test --filter SeshboardUITests

install: build-release install-hooks
	cp .build/release/seshboard-cli ~/.local/bin/seshboard-cli
	pkill -f SeshboardApp || true
	sleep 0.5
	.build/release/SeshboardApp &

install-cli: build-release
	cp .build/release/seshboard-cli ~/.local/bin/seshboard-cli

install-app: build-release
	pkill -f SeshboardApp || true
	sleep 0.5
	.build/release/SeshboardApp &

install-hooks:
	bash scripts/install-hooks.sh

clean:
	swift package clean

resolve:
	swift package resolve

kill-build:
	pkill -9 -f swift-build || true
	pkill -9 -f swift-test || true
	pkill -9 -f swift-frontend || true
	@echo "killed stale SwiftPM processes"
