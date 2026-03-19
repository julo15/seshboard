import SwiftUI
import SeshctlCore

struct UserTurnView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(Color.accentColor)

            Text(text)
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
                Text(text)
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

    var body: some View {
        switch turn {
        case .userMessage(let text, _):
            UserTurnView(text: text)
        case .assistantMessage(let text, let toolCalls, _):
            AssistantTurnView(
                text: text,
                toolCalls: toolCalls,
                toolCallSummary: turn.toolCallSummary,
                showHeader: showHeader
            )
        }
    }
}
