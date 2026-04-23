import Foundation
import Testing

@testable import SeshctlCore

@Suite("TerminalApp - from(termProgram:)")
struct TerminalAppTermProgramTests {

    @Test("Maps known TERM_PROGRAM values to correct apps")
    func knownValues() {
        #expect(TerminalApp.from(termProgram: "Apple_Terminal") == .terminal)
        #expect(TerminalApp.from(termProgram: "iTerm.app") == .iterm2)
        #expect(TerminalApp.from(termProgram: "warpterm") == .warp)
        #expect(TerminalApp.from(termProgram: "ghostty") == .ghostty)
        #expect(TerminalApp.from(termProgram: "vscode") == .vscode)
    }

    @Test("Matching is case-insensitive")
    func caseInsensitive() {
        #expect(TerminalApp.from(termProgram: "Ghostty") == .ghostty)
        #expect(TerminalApp.from(termProgram: "GHOSTTY") == .ghostty)
        #expect(TerminalApp.from(termProgram: "VSCode") == .vscode)
    }

    @Test("Returns nil for unknown values")
    func unknownValues() {
        #expect(TerminalApp.from(termProgram: "tmux") == nil)
        #expect(TerminalApp.from(termProgram: "") == nil)
        #expect(TerminalApp.from(termProgram: "alacritty") == nil)
    }
}

@Suite("TerminalApp - from(environment:)")
struct TerminalAppFromEnvironmentTests {

    @Test("CMUX_WORKSPACE_ID alone returns .cmux")
    func cmuxWorkspaceIdReturnsCmux() {
        let env = ["CMUX_WORKSPACE_ID": "workspace:2"]
        #expect(TerminalApp.from(environment: env) == .cmux)
    }

    @Test("CMUX_SOCKET_PATH alone returns .cmux")
    func cmuxSocketPathReturnsCmux() {
        let env = ["CMUX_SOCKET_PATH": "/tmp/cmux.sock"]
        #expect(TerminalApp.from(environment: env) == .cmux)
    }

    @Test("TERM_PROGRAM=ghostty alone returns .ghostty")
    func ghosttyTermProgramReturnsGhostty() {
        let env = ["TERM_PROGRAM": "ghostty"]
        #expect(TerminalApp.from(environment: env) == .ghostty)
    }

    @Test("CMUX_WORKSPACE_ID beats TERM_PROGRAM=ghostty")
    func cmuxBeatsGhosttyWhenBothSet() {
        // cmux spawns shells with TERM_PROGRAM=ghostty; the CMUX_* vars are
        // the tiebreaker so we correctly classify the host as cmux.
        let env = [
            "CMUX_WORKSPACE_ID": "workspace:2",
            "TERM_PROGRAM": "ghostty",
        ]
        #expect(TerminalApp.from(environment: env) == .cmux)
    }

    @Test("Empty environment returns nil")
    func emptyEnvironmentReturnsNil() {
        #expect(TerminalApp.from(environment: [:]) == nil)
    }

    @Test("TERM_PROGRAM=Apple_Terminal returns .terminal")
    func appleTerminalReturnsTerminal() {
        let env = ["TERM_PROGRAM": "Apple_Terminal"]
        #expect(TerminalApp.from(environment: env) == .terminal)
    }

    @Test("Unknown TERM_PROGRAM returns nil")
    func unknownTermProgramReturnsNil() {
        let env = ["TERM_PROGRAM": "some-new-terminal"]
        #expect(TerminalApp.from(environment: env) == nil)
    }
}
