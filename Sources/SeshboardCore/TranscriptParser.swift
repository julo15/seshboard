import Foundation

/// Parses Claude Code JSONL transcripts into conversation turns.
public enum TranscriptParser {

    /// Compute the transcript file URL for a session.
    /// Returns nil if the session has no conversationId.
    public static func transcriptURL(for session: Session) -> URL? {
        guard let convId = session.conversationId else { return nil }
        let encoded = encodePath(session.directory)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home
            .appendingPathComponent(".claude/projects/\(encoded)/\(convId).jsonl")
        return path
    }

    /// Encode a directory path the way Claude Code does:
    /// `/Users/foo/bar` → `-Users-foo-bar`
    public static func encodePath(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "-")
    }

    /// Parse a JSONL transcript file into conversation turns.
    public static func parse(url: URL) throws -> [ConversationTurn] {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    /// Parse JSONL data into conversation turns.
    public static func parse(data: Data) throws -> [ConversationTurn] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

        // First pass: collect raw entries, grouping assistant messages by message.id
        var assistantGroups: [(id: String, timestamp: Date, contentBlocks: [[String: Any]])] = []
        var assistantIndex: [String: Int] = [:]  // message.id → index in assistantGroups
        var userTurns: [(text: String, timestamp: Date)] = []

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            // Only process user and assistant types
            guard type == "user" || type == "assistant" else { continue }

            let timestamp = parseTimestamp(json["timestamp"], formatter: isoFormatter) ?? Date.distantPast
            guard let message = json["message"] as? [String: Any] else { continue }

            if type == "user" {
                if let text = extractUserText(from: message) {
                    userTurns.append((text: text, timestamp: timestamp))
                }
            } else if type == "assistant" {
                guard let messageId = message["id"] as? String,
                      let contentArray = message["content"] as? [[String: Any]] else { continue }

                if let idx = assistantIndex[messageId] {
                    assistantGroups[idx].contentBlocks.append(contentsOf: contentArray)
                    // Use latest timestamp
                    assistantGroups[idx].timestamp = timestamp
                } else {
                    assistantIndex[messageId] = assistantGroups.count
                    assistantGroups.append((id: messageId, timestamp: timestamp, contentBlocks: contentArray))
                }
            }
        }

        // Second pass: convert grouped data into ConversationTurn
        var turns: [ConversationTurn] = []

        // Collect all turns with timestamps for sorting
        for user in userTurns {
            turns.append(.userMessage(text: user.text, timestamp: user.timestamp))
        }

        for group in assistantGroups {
            let (text, toolCalls) = extractAssistantContent(from: group.contentBlocks)
            // Skip empty assistant turns (e.g., thinking-only)
            if text.isEmpty && toolCalls.isEmpty { continue }
            turns.append(.assistantMessage(text: text, toolCalls: toolCalls, timestamp: group.timestamp))
        }

        // Sort chronologically
        turns.sort { $0.timestamp < $1.timestamp }
        return turns
    }

    // MARK: - Private helpers

    private static func parseTimestamp(_ value: Any?, formatter: ISO8601DateFormatter) -> Date? {
        guard let str = value as? String else { return nil }
        return formatter.date(from: str)
    }

    /// Extract displayable text from a user message.
    /// Returns nil for tool_result messages (API plumbing).
    private static func extractUserText(from message: [String: Any]) -> String? {
        let content = message["content"]

        // String content = direct user prompt
        if let text = content as? String {
            return stripSystemReminders(text)
        }

        // Array content — check if it's all tool_results (skip) or has text
        if let blocks = content as? [[String: Any]] {
            let textBlocks = blocks.filter { ($0["type"] as? String) == "text" }
            if textBlocks.isEmpty { return nil }  // All tool_result — skip
            let text = textBlocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
            let stripped = stripSystemReminders(text)
            return stripped.isEmpty ? nil : stripped
        }

        return nil
    }

    /// Remove <system-reminder>...</system-reminder> tags and their content.
    static func stripSystemReminders(_ text: String) -> String {
        // Use regex to remove system-reminder blocks
        let pattern = "<system-reminder>[\\s\\S]*?</system-reminder>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let result = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract text and tool calls from merged assistant content blocks.
    private static func extractAssistantContent(from blocks: [[String: Any]]) -> (String, [ToolCallSummary]) {
        var textParts: [String] = []
        var toolCalls: [ToolCallSummary] = []

        for block in blocks {
            guard let blockType = block["type"] as? String else { continue }
            switch blockType {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    textParts.append(text)
                }
            case "tool_use":
                if let name = block["name"] as? String {
                    toolCalls.append(ToolCallSummary(toolName: name))
                }
            default:
                // Skip thinking, etc.
                break
            }
        }

        return (textParts.joined(separator: "\n"), toolCalls)
    }
}
