import Foundation
import Testing

@testable import SeshctlCore

@Suite("TranscriptBridgeScanner")
struct TranscriptBridgeScannerTests {

    @Test("empty transcript returns nil")
    func empty() {
        #expect(TranscriptBridgeScanner.extractBridgedRemoteId(transcript: "") == nil)
    }

    @Test("transcript with no bridge_status events returns nil")
    func noBridgeEvents() {
        let transcript = """
        {"type":"permission-mode","permissionMode":"bypassPermissions","sessionId":"local-uuid"}
        {"type":"user","message":{"role":"user","content":"hi"}}
        {"type":"assistant","message":{"role":"assistant","content":"hello"}}
        """
        #expect(TranscriptBridgeScanner.extractBridgedRemoteId(transcript: transcript) == nil)
    }

    @Test("single bridge_status event returns its cse_id")
    func singleBridge() {
        let transcript = """
        {"type":"user","message":{"role":"user","content":"hi"}}
        {"type":"system","subtype":"bridge_status","content":"/remote-control is active","url":"https://claude.ai/code/session_01KMrnTTXLeFkzbyWTU8VKAX","timestamp":"2026-04-21T16:07:43.779Z"}
        """
        let id = TranscriptBridgeScanner.extractBridgedRemoteId(transcript: transcript)
        #expect(id == "cse_01KMrnTTXLeFkzbyWTU8VKAX")
    }

    @Test("multiple bridge_status events — most recent (last in file) wins")
    func multipleBridgesLatestWins() {
        let transcript = """
        {"type":"system","subtype":"bridge_status","url":"https://claude.ai/code/session_FIRST"}
        {"type":"user","message":{"role":"user","content":"later activity"}}
        {"type":"system","subtype":"bridge_status","url":"https://claude.ai/code/session_SECOND"}
        """
        let id = TranscriptBridgeScanner.extractBridgedRemoteId(transcript: transcript)
        #expect(id == "cse_SECOND")
    }

    @Test("malformed JSON lines don't crash the scan and don't affect later matches")
    func malformedLinesIgnored() {
        let transcript = """
        not json at all
        {"type":"system","subtype":"bridge_status","url":"https://claude.ai/code/session_GOOD"}
        {"incomplete":
        """
        let id = TranscriptBridgeScanner.extractBridgedRemoteId(transcript: transcript)
        #expect(id == "cse_GOOD")
    }

    @Test("bridge_status without url field is skipped")
    func missingUrlField() {
        let transcript = """
        {"type":"system","subtype":"bridge_status","content":"something else"}
        {"type":"system","subtype":"bridge_status","url":"https://claude.ai/code/session_REAL"}
        """
        let id = TranscriptBridgeScanner.extractBridgedRemoteId(transcript: transcript)
        #expect(id == "cse_REAL")
    }

    @Test("non-bridge system events are ignored")
    func nonBridgeSystemEvents() {
        let transcript = """
        {"type":"system","subtype":"other_event","url":"https://claude.ai/code/session_IGNORE"}
        {"type":"user","message":{"role":"user","content":"hi"}}
        """
        #expect(TranscriptBridgeScanner.extractBridgedRemoteId(transcript: transcript) == nil)
    }

    @Test("url without the /code/session_ marker returns nil")
    func otherUrlShape() {
        let transcript = """
        {"type":"system","subtype":"bridge_status","url":"https://claude.ai/chat/abc"}
        """
        #expect(TranscriptBridgeScanner.extractBridgedRemoteId(transcript: transcript) == nil)
    }

    @Test("url with trailing path/query/fragment still extracts a clean cse_id")
    func urlWithTrailingJunk() {
        let transcript = """
        {"type":"system","subtype":"bridge_status","url":"https://claude.ai/code/session_CLEAN/tab?foo=bar"}
        """
        let id = TranscriptBridgeScanner.extractBridgedRemoteId(transcript: transcript)
        #expect(id == "cse_CLEAN")
    }

    @Test("reads a real temp file on disk")
    func readsFileFromDisk() throws {
        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("\(UUID().uuidString).jsonl")
        let content = """
        {"type":"system","subtype":"bridge_status","url":"https://claude.ai/code/session_DISK"}
        """
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let id = TranscriptBridgeScanner.extractBridgedRemoteId(transcriptPath: path)
        #expect(id == "cse_DISK")
    }

    @Test("missing file returns nil (doesn't throw)")
    func missingFile() {
        let id = TranscriptBridgeScanner.extractBridgedRemoteId(
            transcriptPath: "/tmp/does-not-exist-\(UUID().uuidString).jsonl"
        )
        #expect(id == nil)
    }
}
