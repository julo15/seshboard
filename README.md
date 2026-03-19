# Seshboard

A macOS session manager for terminal-based workflows. Tracks coding sessions across Terminal.app, iTerm2, and VS Code terminals, with a native menu bar app and CLI.

## Requirements

- macOS 13+
- Swift 6.0+ (comes with Xcode 16+)
- [jq](https://jqlang.github.io/jq/) (for `make install-hooks`)

## Install

### Build from source

```sh
git clone https://github.com/julo15/seshboard.git
cd seshboard
make install    # builds release + installs CLI + hooks + launches app
```

`make install` builds a release, installs `seshboard-cli` to `~/.local/bin`, registers hooks, and launches the menu bar app. Make sure `~/.local/bin` is on your `PATH`.

To uninstall everything:

```sh
make uninstall  # stops app + removes CLI + unregisters hooks
```

### VS Code extension

The extension lets Seshboard focus VS Code terminal tabs by PID.

```sh
cd vscode-extension
npm install
npm run build
npm exec -- @vscode/vsce package --allow-missing-repository
code --install-extension seshboard-*.vsix
rm seshboard-*.vsix
```

> **Tip:** If you use VS Code Insiders, replace `code` with `code-insiders`.

### LLM CLI hooks

Seshboard tracks session status through hooks for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/hooks) and Codex. `make install` registers these automatically. To manage hooks separately:

```sh
make install-hooks    # register hooks for Claude Code and Codex
make uninstall-hooks  # remove hooks for Claude Code and Codex
```

Hook scripts are installed to `~/.local/share/seshboard/hooks/{claude,codex}/` and registered in `~/.claude/settings.json` and `~/.agents/hooks.json` respectively. Both commands are idempotent.

## Usage

Press **Cmd+Shift+S** to toggle the session panel. From the panel:

- **j / k** or **Arrow keys** — navigate sessions
- **gg** — jump to top
- **G** — jump to bottom
- **Enter** — focus the selected session's terminal
- **/** — search/filter sessions
- **Esc** — dismiss the panel

## Development

```sh
make build          # debug build
make test           # run all tests
make run-app        # run menu bar app (debug)
make run-cli ARGS="list"  # run CLI with arguments
make help           # see all available commands
```
