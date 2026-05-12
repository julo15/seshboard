.DEFAULT_GOAL := help
.PHONY: help build build-release bundle sign make-dmg dist reinstall cert-setup run-app run-cli test test-core test-ui clean resolve kill-build install-vscode uninstall

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
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "bundle" "Assemble dist/Seshctl.app from release build (no signing)"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "sign" "Sign dist/Seshctl.app with self-signed cert"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "make-dmg" "Create dist/Seshctl-<VERSION>.dmg from signed app"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "dist" "Full release artifact: bundle + sign + make-dmg"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "reinstall" "Dev iteration: bundle + sign + replace /Applications/Seshctl.app + relaunch (no DMG)"
	@echo ""
	@printf "  $(DIM)setup$(RESET)\n"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "cert-setup" "Create the Seshctl Self-Signed code-signing identity (one-time)"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "install-vscode" "Build + install VS Code extension"
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
	@printf "  $(DIM)remove$(RESET)\n"
	@printf "  $(CYAN)%-14s$(RESET) %s\n" "uninstall" "Remove all seshctl integrations and trash /Applications/Seshctl.app"
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

bundle:
	bash scripts/build-app-bundle.sh

sign:
	bash scripts/sign-app.sh

make-dmg:
	bash scripts/make-dmg.sh

dist: bundle sign make-dmg

# Dev iteration: rebuild + sign + drop the .app straight into /Applications.
# Skips DMG creation (use `make dist` for the user-facing flow). Designed
# for tight iteration on app code; preserves the marker file in
# ~/Library/Application Support/Seshctl so the welcome panel doesn't re-fire.
# To force the welcome panel on next launch, run `seshctl uninstall`
# (or trash the marker file) before `make reinstall`.
reinstall: bundle sign
	@pkill -f 'Seshctl.app/Contents/MacOS/SeshctlApp' 2>/dev/null || true
	@sleep 0.3
	@if [ -d /Applications/Seshctl.app ]; then \
		trash /Applications/Seshctl.app 2>/dev/null || rm -rf /Applications/Seshctl.app; \
	fi
	cp -R dist/Seshctl.app /Applications/Seshctl.app
	@# Run the installer against the freshly-deployed bundle so hook scripts,
	@# settings.json entries, and the CLI symlink refresh on every reinstall.
	@# AppDelegate's welcome-panel check is marker-gated and would skip this
	@# silently; calling the CLI directly bypasses the gate.
	/Applications/Seshctl.app/Contents/MacOS/seshctl-cli install
	open /Applications/Seshctl.app
	@echo ""
	@printf "  $(BOLD)Seshctl reinstalled$(RESET) and relaunched from /Applications.\n"
	@echo ""

cert-setup:
	bash scripts/generate-self-signed-cert.sh

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

install-vscode:
	cd vscode-extension && npm install && npm run build
	cd vscode-extension && npm exec -- @vscode/vsce package --allow-missing-repository
	code --install-extension vscode-extension/seshctl-*.vsix
	rm vscode-extension/seshctl-*.vsix
	@echo "VS Code extension installed — reload VS Code to activate"

uninstall:
	@if command -v seshctl >/dev/null 2>&1; then \
		seshctl uninstall; \
	elif command -v seshctl-cli >/dev/null 2>&1; then \
		seshctl-cli uninstall; \
	else \
		echo "seshctl CLI not found on PATH — already uninstalled?"; \
	fi
	@if [ -d /Applications/Seshctl.app ]; then \
		trash /Applications/Seshctl.app 2>/dev/null || rm -rf /Applications/Seshctl.app; \
		echo "trashed /Applications/Seshctl.app"; \
	fi

clean:
	swift package clean

resolve:
	swift package resolve

kill-build:
	pkill -9 -f swift-build || true
	pkill -9 -f swift-test || true
	pkill -9 -f swift-frontend || true
	@echo "killed stale SwiftPM processes"
