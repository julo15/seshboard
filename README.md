# Seshboard

A macOS session manager for terminal-based workflows. Tracks coding sessions across Terminal.app, iTerm2, and VS Code terminals, with a native menu bar app and CLI.

## Requirements

- macOS 13+
- Swift 6.0+ (comes with Xcode 16+)

## Install

### Build from source

```sh
git clone https://github.com/julo15/seshboard.git
cd seshboard
make install    # builds release + installs CLI to ~/.local/bin
```

This gives you the `seshboard-cli` command. Make sure `~/.local/bin` is on your `PATH`.

To also run the menu bar app:

```sh
make restart    # builds release + launches SeshboardApp
```

### VS Code extension

The extension lets Seshboard focus VS Code terminal tabs by PID.

```sh
cd vscode-extension
npm install
npm run build
```

Then install it into VS Code:

```sh
code --install-extension vscode-extension/
```

> **Tip:** If you use VS Code Insiders, use `code-insiders --install-extension vscode-extension/` instead.

### Claude Code hooks

Seshboard tracks session status through [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks). Hook scripts live in `hooks/claude/` and need to be registered in your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      { "command": "/path/to/seshboard/hooks/claude/session-start.sh" }
    ],
    "UserPromptSubmit": [
      { "command": "/path/to/seshboard/hooks/claude/user-prompt.sh" }
    ],
    "Stop": [
      { "command": "/path/to/seshboard/hooks/claude/stop.sh" }
    ],
    "SessionEnd": [
      { "command": "/path/to/seshboard/hooks/claude/session-end.sh" }
    ]
  }
}
```

Replace `/path/to/seshboard` with wherever you cloned the repo.

## Usage

Press **Cmd+Shift+S** to toggle the session panel. From the panel:

- **j / k** or **Arrow keys** — navigate sessions
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
