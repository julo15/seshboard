import Foundation
import Testing

@testable import SeshboardCore

@Suite("TranscriptParser")
struct TranscriptParserTests {

    @Test("Encodes path correctly")
    func encodesPath() {
        #expect(TranscriptParser.encodePath("/Users/foo/bar") == "-Users-foo-bar")
        #expect(TranscriptParser.encodePath("/") == "-")
    }

    @Test("Returns nil URL when no conversationId")
    func noConversationId() {
        let session = makeSession(conversationId: nil)
        #expect(TranscriptParser.transcriptURL(for: session) == nil)
    }

    @Test("Returns URL when conversationId present")
    func withConversationId() {
        let session = makeSession(conversationId: "abc-123", directory: "/Users/foo/bar")
        let url = TranscriptParser.transcriptURL(for: session)
        #expect(url != nil)
        #expect(url?.path.hasSuffix("-Users-foo-bar/abc-123.jsonl") == true)
    }

    @Test("Parses user text message (string content)")
    func parsesUserText() throws {
        let jsonl = makeUserLine(content: "\"hello world\"")
        let turns = try TranscriptParser.parse(data: Data(jsonl.utf8))

        #expect(turns.count == 1)
        if case .userMessage(let text, _) = turns[0] {
            #expect(text == "hello world")
        } else {
            Issue.record("Expected userMessage")
        }
    }

    @Test("Parses assistant text message")
    func parsesAssistantText() throws {
        let jsonl = makeAssistantLine(messageId: "msg_1", contentBlocks: [
            "{\"type\": \"text\", \"text\": \"Here is my response.\"}"
        ])
        let turns = try TranscriptParser.parse(data: Data(jsonl.utf8))

        #expect(turns.count == 1)
        if case .assistantMessage(let text, let tools, _) = turns[0] {
            #expect(text == "Here is my response.")
            #expect(tools.isEmpty)
        } else {
            Issue.record("Expected assistantMessage")
        }
    }

    @Test("Merges content blocks by message.id")
    func mergesBlocks() throws {
        let line1 = makeAssistantLine(messageId: "msg_1", contentBlocks: [
            "{\"type\": \"text\", \"text\": \"Starting...\"}"
        ], timestamp: "2026-01-01T00:00:01.000Z")
        let line2 = makeAssistantLine(messageId: "msg_1", contentBlocks: [
            "{\"type\": \"tool_use\", \"id\": \"t1\", \"name\": \"Read\", \"input\": {}}"
        ], timestamp: "2026-01-01T00:00:02.000Z")
        let line3 = makeAssistantLine(messageId: "msg_1", contentBlocks: [
            "{\"type\": \"tool_use\", \"id\": \"t2\", \"name\": \"Edit\", \"input\": {}}"
        ], timestamp: "2026-01-01T00:00:03.000Z")

        let jsonl = [line1, line2, line3].joined(separator: "\n")
        let turns = try TranscriptParser.parse(data: Data(jsonl.utf8))

        #expect(turns.count == 1)
        if case .assistantMessage(let text, let tools, _) = turns[0] {
            #expect(text == "Starting...")
            #expect(tools.count == 2)
            #expect(tools[0].toolName == "Read")
            #expect(tools[1].toolName == "Edit")
        } else {
            Issue.record("Expected assistantMessage")
        }
    }

    @Test("Filters progress entries")
    func filtersProgress() throws {
        let progress = """
        {"type": "progress", "data": {"type": "hook_progress"}, "timestamp": "2026-01-01T00:00:00.000Z"}
        """
        let user = makeUserLine(content: "\"hello\"")
        let jsonl = [progress, user].joined(separator: "\n")
        let turns = try TranscriptParser.parse(data: Data(jsonl.utf8))

        #expect(turns.count == 1)
    }

    @Test("Filters tool_result user messages")
    func filtersToolResults() throws {
        let toolResult = """
        {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}, "timestamp": "2026-01-01T00:00:00.000Z", "uuid": "u1"}
        """
        let turns = try TranscriptParser.parse(data: Data(toolResult.utf8))
        #expect(turns.isEmpty)
    }

    @Test("Strips system-reminder tags")
    func stripsSystemReminders() {
        let input = "hello <system-reminder>secret stuff</system-reminder> world"
        let result = TranscriptParser.stripInternalTags(input)
        #expect(result == "hello  world")
    }

    @Test("Strips multiline system-reminder tags")
    func stripsMultilineSystemReminders() {
        let input = "hello\n<system-reminder>\nline1\nline2\n</system-reminder>\nworld"
        let result = TranscriptParser.stripInternalTags(input)
        #expect(result == "hello\n\nworld")
    }

    @Test("Strips local-command-stdout tags and skips empty turns")
    func stripsLocalCommandTags() {
        let input = "<local-command-stdout>Set model to Opus 4.6</local-command-stdout>"
        let result = TranscriptParser.stripInternalTags(input)
        #expect(result == "")
    }

    @Test("Strips thinking blocks from assistant content")
    func stripsThinking() throws {
        let line1 = makeAssistantLine(messageId: "msg_1", contentBlocks: [
            "{\"type\": \"thinking\", \"thinking\": \"secret\", \"signature\": \"abc\"}"
        ], timestamp: "2026-01-01T00:00:01.000Z")
        let line2 = makeAssistantLine(messageId: "msg_1", contentBlocks: [
            "{\"type\": \"text\", \"text\": \"visible response\"}"
        ], timestamp: "2026-01-01T00:00:02.000Z")

        let jsonl = [line1, line2].joined(separator: "\n")
        let turns = try TranscriptParser.parse(data: Data(jsonl.utf8))

        #expect(turns.count == 1)
        if case .assistantMessage(let text, _, _) = turns[0] {
            #expect(text == "visible response")
            #expect(!text.contains("secret"))
        } else {
            Issue.record("Expected assistantMessage")
        }
    }

    @Test("Thinking-only assistant turns are skipped")
    func thinkingOnlySkipped() throws {
        let line = makeAssistantLine(messageId: "msg_1", contentBlocks: [
            "{\"type\": \"thinking\", \"thinking\": \"\", \"signature\": \"abc\"}"
        ])
        let turns = try TranscriptParser.parse(data: Data(line.utf8))
        #expect(turns.isEmpty)
    }

    @Test("Tool call summary from assistant turn")
    func toolCallSummary() throws {
        let lines = [
            makeAssistantLine(messageId: "msg_1", contentBlocks: [
                "{\"type\": \"text\", \"text\": \"Let me check.\"}"
            ], timestamp: "2026-01-01T00:00:01.000Z"),
            makeAssistantLine(messageId: "msg_1", contentBlocks: [
                "{\"type\": \"tool_use\", \"id\": \"t1\", \"name\": \"Read\", \"input\": {}}"
            ], timestamp: "2026-01-01T00:00:02.000Z"),
            makeAssistantLine(messageId: "msg_1", contentBlocks: [
                "{\"type\": \"tool_use\", \"id\": \"t2\", \"name\": \"Read\", \"input\": {}}"
            ], timestamp: "2026-01-01T00:00:03.000Z"),
            makeAssistantLine(messageId: "msg_1", contentBlocks: [
                "{\"type\": \"tool_use\", \"id\": \"t3\", \"name\": \"Edit\", \"input\": {}}"
            ], timestamp: "2026-01-01T00:00:04.000Z"),
        ]
        let jsonl = lines.joined(separator: "\n")
        let turns = try TranscriptParser.parse(data: Data(jsonl.utf8))

        #expect(turns.count == 1)
        #expect(turns[0].toolCallSummary == "Read \u{00d7}2, Edit \u{00d7}1")
    }

    @Test("Empty data returns empty array")
    func emptyData() throws {
        let turns = try TranscriptParser.parse(data: Data())
        #expect(turns.isEmpty)
    }

    @Test("Chronological order")
    func chronologicalOrder() throws {
        let assistant = makeAssistantLine(messageId: "msg_1", contentBlocks: [
            "{\"type\": \"text\", \"text\": \"response\"}"
        ], timestamp: "2026-01-01T00:00:02.000Z")
        let user = makeUserLine(content: "\"question\"", timestamp: "2026-01-01T00:00:01.000Z")

        // Put assistant first in the file, but user has earlier timestamp
        let jsonl = [assistant, user].joined(separator: "\n")
        let turns = try TranscriptParser.parse(data: Data(jsonl.utf8))

        #expect(turns.count == 2)
        if case .userMessage = turns[0] {} else { Issue.record("Expected user first") }
        if case .assistantMessage = turns[1] {} else { Issue.record("Expected assistant second") }
    }

    @Test("Multiple assistant messages stay separate")
    func separateAssistantMessages() throws {
        let line1 = makeAssistantLine(messageId: "msg_1", contentBlocks: [
            "{\"type\": \"text\", \"text\": \"first\"}"
        ], timestamp: "2026-01-01T00:00:01.000Z")
        let line2 = makeAssistantLine(messageId: "msg_2", contentBlocks: [
            "{\"type\": \"text\", \"text\": \"second\"}"
        ], timestamp: "2026-01-01T00:00:02.000Z")

        let jsonl = [line1, line2].joined(separator: "\n")
        let turns = try TranscriptParser.parse(data: Data(jsonl.utf8))

        #expect(turns.count == 2)
    }

    // MARK: - Codex parsing

    @Test("Parses Codex transcript with user and assistant turns")
    func parsesCodexTranscript() throws {
        let lines = [
            // Developer message — should be skipped
            """
            {"timestamp":"2026-03-18T01:15:14.280Z","type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"<permissions instructions>..."}]}}
            """,
            // User message
            """
            {"timestamp":"2026-03-18T01:15:14.281Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"study the cancellation workflow"}]}}
            """,
            // Assistant message
            """
            {"timestamp":"2026-03-18T01:15:15.100Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"I'm reviewing the repo evidence for cancellations."}],"phase":"commentary"}}
            """,
            // session_meta — should be skipped
            """
            {"timestamp":"2026-03-18T01:15:13.000Z","type":"session_meta","payload":{"model":"o4-mini"}}
            """,
            // reasoning — should be skipped
            """
            {"timestamp":"2026-03-18T01:15:14.500Z","type":"response_item","payload":{"type":"reasoning","content":[]}}
            """,
        ]
        let jsonl = lines.joined(separator: "\n")
        let turns = try TranscriptParser.parseCodex(data: Data(jsonl.utf8))

        #expect(turns.count == 2)
        if case .userMessage(let text, _) = turns[0] {
            #expect(text == "study the cancellation workflow")
        } else {
            Issue.record("Expected userMessage first, got \(turns[0])")
        }
        if case .assistantMessage(let text, let tools, _) = turns[1] {
            #expect(text == "I'm reviewing the repo evidence for cancellations.")
            #expect(tools.isEmpty)
        } else {
            Issue.record("Expected assistantMessage second, got \(turns[1])")
        }
    }

    @Test("Codex parser handles timestamps without fractional seconds")
    func codexTimestampsWithoutFractional() throws {
        let lines = [
            """
            {"timestamp":"2026-03-18T01:15:14Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"hello"}]}}
            """,
            """
            {"timestamp":"2026-03-18T01:15:15Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hi there"}]}}
            """,
        ]
        let jsonl = lines.joined(separator: "\n")
        let turns = try TranscriptParser.parseCodex(data: Data(jsonl.utf8))

        #expect(turns.count == 2)
        // Verify timestamps are NOT distantPast (the bug was that timestamps without
        // fractional seconds failed to parse, falling back to Date.distantPast)
        #expect(turns[0].timestamp != Date.distantPast)
        #expect(turns[1].timestamp != Date.distantPast)
        #expect(turns[0].timestamp < turns[1].timestamp)
    }

    @Test("Codex parser skips developer messages")
    func codexSkipsDeveloper() throws {
        let jsonl = """
        {"timestamp":"2026-03-18T01:15:14.280Z","type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"system instructions here"}]}}
        """
        let turns = try TranscriptParser.parseCodex(data: Data(jsonl.utf8))
        #expect(turns.isEmpty)
    }

    // MARK: - Helpers

    private func makeSession(conversationId: String? = nil, directory: String = "/tmp") -> Session {
        Session(
            id: "test-id",
            conversationId: conversationId,
            tool: .claude,
            directory: directory,
            lastAsk: nil,
            status: .idle,
            pid: 1234,
            hostAppBundleId: nil,
            hostAppName: nil,
            windowId: nil,
            transcriptPath: nil,
            startedAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeUserLine(content: String, timestamp: String = "2026-01-01T00:00:00.000Z") -> String {
        """
        {"type": "user", "message": {"role": "user", "content": \(content)}, "timestamp": "\(timestamp)", "uuid": "u-\(UUID().uuidString)"}
        """
    }

    private func makeAssistantLine(messageId: String, contentBlocks: [String], timestamp: String = "2026-01-01T00:00:00.000Z") -> String {
        let blocksStr = contentBlocks.joined(separator: ", ")
        return """
        {"type": "assistant", "message": {"id": "\(messageId)", "role": "assistant", "content": [\(blocksStr)]}, "timestamp": "\(timestamp)", "uuid": "a-\(UUID().uuidString)"}
        """
    }
}
