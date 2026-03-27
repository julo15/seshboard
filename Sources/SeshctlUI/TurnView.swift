import SwiftUI
import SeshctlCore

/// Build a `Text` view that highlights all occurrences of `query` (case-insensitive).
private func highlightedText(_ text: String, query: String?, isCurrentMatch: Bool) -> Text {
    guard let query, !query.isEmpty else {
        return Text(text)
    }

    let lowerText = text.lowercased()
    let lowerQuery = query.lowercased()

    var parts: [Text] = []
    var currentIndex = text.startIndex

    while currentIndex < text.endIndex,
          let range = lowerText.range(of: lowerQuery, range: currentIndex..<text.endIndex) {
        // Add text before match
        if currentIndex < range.lowerBound {
            parts.append(Text(text[currentIndex..<range.lowerBound]))
        }
        // Add highlighted match — use modifiers that return Text so concatenation works.
        var match = Text(text[range])
            .foregroundColor(isCurrentMatch ? .black : .primary)
            .underline(true, color: isCurrentMatch ? .orange : .yellow)
        if isCurrentMatch {
            match = match.bold()
        }
        parts.append(match)
        currentIndex = range.upperBound
    }

    // Add remaining text
    if currentIndex < text.endIndex {
        parts.append(Text(text[currentIndex..<text.endIndex]))
    }

    if parts.isEmpty {
        return Text(text)
    }

    return parts.dropFirst().reduce(parts[0]) { $0 + $1 }
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
