import SwiftUI
import SeshctlCore

/// Build a `Text` view that highlights all occurrences of `query` (case-insensitive)
/// using background color via AttributedString.
private func highlightedText(_ text: String, query: String?, isCurrentMatch: Bool) -> Text {
    guard let query, !query.isEmpty else {
        return Text(text)
    }

    var attributed = AttributedString(text)
    let lowerText = text.lowercased()
    let lowerQuery = query.lowercased()

    var searchStart = lowerText.startIndex
    while searchStart < lowerText.endIndex,
          let range = lowerText.range(of: lowerQuery, range: searchStart..<lowerText.endIndex) {
        // Convert String.Index range to AttributedString.Index range via character offsets
        let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        let endOffset = text.distance(from: text.startIndex, to: range.upperBound)
        let attrStart = attributed.characters.index(attributed.startIndex, offsetBy: startOffset)
        let attrEnd = attributed.characters.index(attributed.startIndex, offsetBy: endOffset)

        attributed[attrStart..<attrEnd].backgroundColor = isCurrentMatch
            ? .yellow.opacity(0.5)
            : .yellow.opacity(0.25)

        searchStart = range.upperBound
    }

    return Text(attributed)
}

struct UserTurnView: View {
    let text: String
    var highlightText: String? = nil
    var isCurrentMatch: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(Color.accentColor)

            highlightedText(text, query: highlightText, isCurrentMatch: isCurrentMatch)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.06))
    }
}

struct AssistantTurnView: View {
    let text: String
    let toolCalls: [ToolCallSummary]
    let toolCallSummary: String?
    var showHeader: Bool = true
    var highlightText: String? = nil
    var isCurrentMatch: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showHeader {
                Text("Claude")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if let summary = toolCallSummary {
                Text(summary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            }

            if !text.isEmpty {
                highlightedText(text, query: highlightText, isCurrentMatch: isCurrentMatch)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .opacity(0.85)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct TurnView: View {
    let turn: ConversationTurn
    var showHeader: Bool = true
    var highlightText: String? = nil
    var isCurrentMatch: Bool = false

    var body: some View {
        switch turn {
        case .userMessage(let text, _):
            UserTurnView(text: text, highlightText: highlightText, isCurrentMatch: isCurrentMatch)
        case .assistantMessage(let text, let toolCalls, _):
            AssistantTurnView(
                text: text,
                toolCalls: toolCalls,
                toolCallSummary: turn.toolCallSummary,
                showHeader: showHeader,
                highlightText: highlightText,
                isCurrentMatch: isCurrentMatch
            )
        }
    }
}
