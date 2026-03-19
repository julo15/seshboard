.DEFAULT_GOAL := help
.PHONY: help build build-release run-app run-cli test test-core test-ui clean resolve kill-build install install-cli install-app install-hooks uninstall uninstall-cli uninstall-app uninstall-hooks

# Colors
CYAN   := \033[36m
DIM    := \033[2m
BOLD   := \033[1m
RESET  := \033[0m

help:
	@printf "$(BOLD)seshctl$(RESET) $(DIM)commands$(RESET)\n\n"
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
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "test-core" "Run SeshctlCore tests"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "test-ui" "Run SeshctlUI tests"
	@echo ""
	@printf "  $(DIM)install$(RESET)\n"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "install" "Build release + install CLI + hooks + restart app"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "install-cli" "Build release + install CLI to ~/.local/bin"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "install-app" "Build release + restart SeshctlApp"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "install-hooks" "Register Claude Code and Codex hooks"
	@echo ""
	@printf "  $(DIM)uninstall$(RESET)\n"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "uninstall" "Stop app + remove CLI + unregister hooks"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "uninstall-cli" "Remove CLI from ~/.local/bin"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "uninstall-app" "Stop SeshctlApp"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "uninstall-hooks" "Remove Claude Code and Codex hooks"
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
	swift run SeshctlApp

run-cli:
	swift run seshctl-cli $(ARGS)

test:
	swift test

test-core:
	swift test --filter SeshctlCoreTests

test-ui:
	swift test --filter SeshctlUITests

install: build-release install-hooks
	cp .build/release/seshctl-cli ~/.local/bin/seshctl-cli
	pkill -f SeshctlApp || true
	sleep 0.5
	.build/release/SeshctlApp &
	@echo ""
	@printf "  $(BOLD)seshctl installed$(RESET)\n"
	@printf "  Press $(CYAN)⌘⇧S$(RESET) to toggle the session panel.\n"
	@echo ""

install-cli: build-release
	cp .build/release/seshctl-cli ~/.local/bin/seshctl-cli

install-app: build-release
	pkill -f SeshctlApp || true
	sleep 0.5
	.build/release/SeshctlApp &

install-hooks:
	bash scripts/install-hooks.sh

uninstall: uninstall-hooks uninstall-app uninstall-cli

uninstall-cli:
	rm -f ~/.local/bin/seshctl-cli
	@echo "removed seshctl-cli from ~/.local/bin"

uninstall-app:
	pkill -f SeshctlApp || true
	@echo "stopped SeshctlApp"

uninstall-hooks:
	seshctl-cli uninstall --all

clean:
	swift package clean

resolve:
	swift package resolve

kill-build:
	pkill -9 -f swift-build || true
	pkill -9 -f swift-test || true
	pkill -9 -f swift-frontend || true
	@echo "killed stale SwiftPM processes"
