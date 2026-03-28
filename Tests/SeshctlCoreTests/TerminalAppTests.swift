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
