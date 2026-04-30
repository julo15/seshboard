import SwiftUI
import SeshctlCore

/// Parses a string as inline-only markdown, preserving whitespace and falling back
/// to plain text on parse failure.
///
/// Limitations: the built-in Foundation parser only renders inline syntax (bold,
/// italic, links, inline code). Block-level constructs like fenced code blocks,
/// lists, and headings are stripped of their markers but not specially formatted.
func markdownAttributed(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: false,
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    )
    if let parsed = try? AttributedString(markdown: text, options: options) {
        return parsed
    }
    return AttributedString(text)
}

/// Renders a message body as either markdown (when search is inactive) or plain
/// text with the existing search-match highlights (when search is active). Keeps
/// the search-active code path intact so the view-model's index-based match
/// navigation continues to line up with on-screen ranges.
struct MessageBodyText: View {
    let text: String
    var isSearchActive: Bool = false
    var query: String? = nil
    var currentMatchRange: Range<String.Index>? = nil

    var body: some View {
        if isSearchActive {
            highlightedText(text, query: query, currentMatchRange: currentMatchRange)
        } else {
            Text(markdownAttributed(text))
        }
    }
}
