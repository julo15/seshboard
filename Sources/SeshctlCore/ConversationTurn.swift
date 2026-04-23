import Foundation

/// Summary of a tool call made by the assistant.
public struct ToolCallSummary: Sendable, Equatable {
    public let toolName: String

    public init(toolName: String) {
        self.toolName = toolName
    }
}

/// A single turn in a conversation, ready for display.
public enum ConversationTurn: Sendable, Equatable, Identifiable {
    case userMessage(text: String, timestamp: Date)
    case assistantMessage(text: String, toolCalls: [ToolCallSummary], timestamp: Date)

    public var id: String {
        switch self {
        case .userMessage(let text, let ts):
            return "user-\(ts.timeIntervalSince1970)-\(StableHash.djb2(text))"
        case .assistantMessage(let text, _, let ts):
            return "assistant-\(ts.timeIntervalSince1970)-\(StableHash.djb2(text))"
        }
    }

    public var timestamp: Date {
        switch self {
        case .userMessage(_, let ts): return ts
        case .assistantMessage(_, _, let ts): return ts
        }
    }

    /// Compact summary of tool calls, e.g. "Read ×3, Edit ×1".
    public var toolCallSummary: String? {
        guard case .assistantMessage(_, let calls, _) = self, !calls.isEmpty else { return nil }
        var counts: [(String, Int)] = []
        var order: [String] = []
        var map: [String: Int] = [:]
        for call in calls {
            if let idx = map[call.toolName] {
                counts[idx].1 += 1
            } else {
                map[call.toolName] = counts.count
                counts.append((call.toolName, 1))
                order.append(call.toolName)
            }
        }
        return counts.map { "\($0.0) \u{00d7}\($0.1)" }.joined(separator: ", ")
    }
}
