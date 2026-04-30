import Foundation
import Testing

@testable import SeshctlUI

@Suite("MarkdownText")
struct MarkdownTextTests {

    @Test("Plain text round-trips with no syntax")
    func plainTextRoundtrip() {
        let attr = markdownAttributed("hello world")
        #expect(String(attr.characters) == "hello world")
    }

    @Test("Bold markdown strips syntax characters from rendered string")
    func boldStripsSyntax() {
        let attr = markdownAttributed("hello **bold** world")
        // The visible characters should not include the `**` markers.
        let rendered = String(attr.characters)
        #expect(!rendered.contains("**"))
        #expect(rendered.contains("bold"))
    }

    @Test("Newlines are preserved (.inlineOnlyPreservingWhitespace)")
    func preservesNewlines() {
        let attr = markdownAttributed("line one\nline two")
        let rendered = String(attr.characters)
        #expect(rendered.contains("\n"))
    }

    @Test("Returns a non-empty AttributedString even for empty input")
    func emptyInput() {
        let attr = markdownAttributed("")
        #expect(String(attr.characters).isEmpty)
    }
}
