import SwiftUI
import SeshctlCore

struct CollapsedToolBlockView: View {
    let turns: [ConversationTurn]
    let counts: BlockCounts

    @State private var expanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(allCalls.indices, id: \.self) { idx in
                    Text(allCalls[idx].displayLabel)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 18)
            .padding(.top, 4)
        } label: {
            Text(summaryLine)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var allCalls: [ToolCallSummary] {
        turns.flatMap { turn -> [ToolCallSummary] in
            if case .assistantMessage(_, let calls, _) = turn { return calls }
            return []
        }
    }

    private var summaryLine: String {
        var parts: [String] = []
        parts.append("\(counts.toolCalls) tool call\(counts.toolCalls == 1 ? "" : "s")")
        parts.append("\(counts.messages) message\(counts.messages == 1 ? "" : "s")")
        if counts.subagents > 0 {
            parts.append("\(counts.subagents) subagent\(counts.subagents == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }
}
