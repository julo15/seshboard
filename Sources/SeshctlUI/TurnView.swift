import SwiftUI
import SeshctlCore

/// Build a `Text` view that highlights query matches (case-insensitive) using background
/// color via AttributedString. When `perWord` is true, each word in the query is highlighted
/// independently. When false, only the exact full phrase is highlighted.
/// The `currentMatchRange` gets a brighter highlight to distinguish it from other matches.
func highlightedText(_ text: String, query: String?, currentMatchRange: Range<String.Index>? = nil, perWord: Bool = false) -> Text {
    guard let query, !query.isEmpty else {
        return Text(text)
    }

    var attributed = AttributedString(text)
    let terms: [String]
    if perWord {
        terms = query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    } else {
        terms = [query]
    }
    if terms.isEmpty { return Text(text) }

    for term in terms {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: term, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: range.upperBound)
            let attrStart = attributed.characters.index(attributed.startIndex, offsetBy: startOffset)
            let attrEnd = attributed.characters.index(attributed.startIndex, offsetBy: endOffset)

            let isCurrent = range == currentMatchRange
            attributed[attrStart..<attrEnd].backgroundColor = isCurrent
                ? .orange.opacity(0.6)
                : .yellow.opacity(0.25)

            searchStart = range.upperBound
        }
    }

    return Text(attributed)
}

struct UserTurnView: View {
    let text: String
    var isSearchActive: Bool = false
    var highlightText: String? = nil
    var currentMatchRange: Range<String.Index>? = nil

    var body: some View {
        MessageBodyText(text: text, isSearchActive: isSearchActive, query: highlightText, currentMatchRange: currentMatchRange)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }
}

struct AssistantTurnView: View {
    let text: String
    var isSearchActive: Bool = false
    var highlightText: String? = nil
    var currentMatchRange: Range<String.Index>? = nil

    var body: some View {
        if !text.isEmpty {
            MessageBodyText(text: text, isSearchActive: isSearchActive, query: highlightText, currentMatchRange: currentMatchRange)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
    }
}

